import XCTVapor
import Fluent
import FluentSQLiteDriver
import BillMindCore
@testable import App

// MARK: - Test doubles

private struct StubOIDCUntangle: OIDCVerifier {
    let identity: VerifiedIdentity
    func verify(idToken: String, provider: OIDCProvider, on req: Request) async throws -> VerifiedIdentity { identity }
}

/// Counts moderation calls so we can prove untangle never re-moderates. Shared via
/// an actor since the spy crosses request isolation.
private actor ModerationCallSpy {
    private(set) var calls = 0
    func bump() { calls += 1 }
}
private struct SpyMod: ModerationClient {
    let spy: ModerationCallSpy
    func score(_ text: String, on req: Request) async throws -> ModerationScores {
        await spy.bump()
        return ModerationScores(categories: [:])
    }
}

final class UntangleTests: XCTestCase {

    // MARK: - app harness (mirrors CaptureTests.makeApp)

    private func makeApp(reasoner: UntangleReasoner = StubUntangleReasoner(),
                         modSpy: ModerationCallSpy? = nil) async throws -> Application {
        let app = try await Application.make(.testing)
        app.databases.use(.sqlite(.memory), as: .sqlite)
        app.migrations.add(CreateInitialSchema())
        try await app.autoMigrate()
        app.jwt.signers.use(.hs256(key: Array("test-signing-key-0123456789abcdef".utf8)))
        let id = VerifiedIdentity(provider: .google, subject: "u1", email: "u1@example.com", isPrivateRelay: false, name: "u1")
        try app.register(collection: AuthController(oidc: StubOIDCUntangle(identity: id)))
        try app.register(collection: TripController())
        try app.register(collection: BillController())
        try app.register(collection: UntangleController(reasoner: reasoner))
        // A CaptureController is registered only so the moderation spy is wired into a
        // live app; untangle must NOT touch it (the noReModeration test asserts 0 calls).
        if let modSpy {
            try app.register(collection: CaptureController(
                moderation: ModerationService(client: SpyMod(spy: modSpy)),
                recognizer: StubRecognizerForUntangle()))
        }
        return app
    }

    private func signInAndTrip(_ app: Application, currency: String = "JPY") async throws -> (AuthTokensDTO, TripDTO) {
        var tokens: AuthTokensDTO!
        try await app.test(.POST, "v1/auth/google",
            beforeRequest: { try $0.content.encode(["idToken": "stub"]) },
            afterResponse: { res async throws in tokens = try res.content.decode(AuthTokensDTO.self) })
        var trip: TripDTO!
        try await app.test(.POST, "v1/trips", headers: ["Authorization": "Bearer \(tokens.accessToken)"],
            beforeRequest: { try $0.content.encode(CreateTripRequest(name: "Osaka", currencyCode: currency, mascot: nil)) },
            afterResponse: { res async throws in trip = try res.content.decode(TripDTO.self) })
        return (tokens, trip)
    }

    /// Registers a second OIDC subject (Apple, u2) and returns their tokens — the
    /// established foreign-owner pattern (mirrors LedgerTests.signInSecondUser).
    private func signInSecondUser(_ app: Application) async throws -> AuthTokensDTO {
        let idB = VerifiedIdentity(provider: .apple, subject: "u2", email: nil, isPrivateRelay: true, name: nil)
        try app.register(collection: AuthController(oidc: StubOIDCUntangle(identity: idB)))
        var b: AuthTokensDTO!
        try await app.test(.POST, "v1/auth/apple",
            beforeRequest: { try $0.content.encode(["idToken": "stub"]) },
            afterResponse: { res async throws in b = try res.content.decode(AuthTokensDTO.self) })
        return b
    }

    // MARK: - request builders

    private func draftDTO(merchant: String? = nil, amount: Decimal? = nil, currency: String = "JPY",
                          category: String? = "food", source: String = "photo") -> BillDraftDTO {
        BillDraftDTO(merchant: merchant, amount: amount, currencyCode: currency,
                     categoryRaw: category, date: nil, source: source)
    }

    private func input(_ cardID: UUID, _ draft: BillDraftDTO, hasPhoto: Bool = false,
                       note: String? = nil, photoHash: String? = nil) -> UntangleInput {
        UntangleInput(cardID: cardID, draft: draft, hasPhoto: hasPhoto, noteText: note, photoHash: photoHash)
    }

    private func post(_ app: Application, _ token: String, _ body: UntangleRequest,
                      _ assert: @escaping (XCTHTTPResponse) async throws -> Void) async throws {
        try await app.test(.POST, "v1/untangle", headers: ["Authorization": "Bearer \(token)"],
            beforeRequest: { try $0.content.encode(body) }, afterResponse: assert)
    }

    // ============================================================
    // L1 · Server — money-critical core (TECH §7)
    // ============================================================

    /// partitionIsTotalAndDisjoint — every input cardID appears in EXACTLY one bucket.
    func testPartitionIsTotalAndDisjoint() async throws {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        // Reasoner fuses {a,b}, dups {c,?} (only c is real for dup so it'll drop) →
        // we use a clean d and a real dup pair {c,d2}. Re-shape: fuse {a,b}, dup needs 2.
        let plan = UntanglePlan(
            fuses: [ProposedFuse(sourceCardIDs: [a, b], merchant: "Diner", proposedAmount: 1000,
                                 currencyCode: "JPY", categoryRaw: "food", date: nil,
                                 amountSourceCardID: a, reason: "note completes photo", confidence: 0.9)],
            duplicates: [ProposedDuplicate(memberCardIDs: [c, d], survivorCardID: c,
                                           tier: "sameDetails", reason: "same merchant+amount")])
        let app = try await makeApp(reasoner: StubUntangleReasoner(plan: plan))
        let (t, trip) = try await signInAndTrip(app)
        let inputs = [
            input(a, draftDTO(merchant: "Diner", amount: 1000)),
            input(b, draftDTO(merchant: nil, amount: nil)),
            input(c, draftDTO(merchant: "Cafe", amount: 500)),
            input(d, draftDTO(merchant: "Cafe", amount: 500)),
        ]
        try await post(app, t.accessToken, UntangleRequest(tripID: trip.id, inputs: inputs)) { res in
            XCTAssertEqual(res.status, .ok)
            let r = try res.content.decode(UntangleResponse.self)
            let inFuse = Set(r.fuseGroups.flatMap(\.sourceCardIDs))
            let inDup = Set(r.duplicateGroups.flatMap(\.memberCardIDs))
            let inClean = Set(r.cleanCardIDs)
            // Total: union covers every input exactly once.
            XCTAssertEqual(inFuse.union(inDup).union(inClean), Set([a, b, c, d]))
            // Disjoint: buckets share nothing.
            XCTAssertTrue(inFuse.isDisjoint(with: inDup))
            XCTAssertTrue(inFuse.isDisjoint(with: inClean))
            XCTAssertTrue(inDup.isDisjoint(with: inClean))
            // Counts add up to the input count (exactly-once).
            XCTAssertEqual(inFuse.count + inDup.count + inClean.count, 4)
        }
        try await app.asyncShutdown()
    }

    /// fusedAmountByteEqualOrTraceNull — a fused amount equals a member's amount and
    /// carries a trace; otherwise the amount is nil AND amountTrace is nil.
    func testFusedAmountByteEqualOrTraceNull() async throws {
        let a = UUID(), b = UUID()
        let plan = UntanglePlan(fuses: [ProposedFuse(
            sourceCardIDs: [a, b], merchant: "Diner", proposedAmount: 1234,
            currencyCode: "JPY", categoryRaw: "food", date: nil,
            amountSourceCardID: a, reason: "fuse", confidence: 0.9)])
        let app = try await makeApp(reasoner: StubUntangleReasoner(plan: plan))
        let (t, trip) = try await signInAndTrip(app)
        let inputs = [
            input(a, draftDTO(amount: 1234), hasPhoto: true),     // photo carries 1234
            input(b, draftDTO(merchant: "Diner", amount: nil), note: "at the diner"),
        ]
        try await post(app, t.accessToken, UntangleRequest(tripID: trip.id, inputs: inputs)) { res in
            let r = try res.content.decode(UntangleResponse.self)
            XCTAssertEqual(r.fuseGroups.count, 1)
            let g = r.fuseGroups[0]
            XCTAssertEqual(g.resolvedDraft.amount, Decimal(1234))   // byte-equal to member a
            XCTAssertNotNil(g.amountTrace)
            XCTAssertEqual(g.amountTrace?.sourceCardID, a)          // traces to the card that had it
        }
        try await app.asyncShutdown()
    }

    /// verbatimPostCheckDropsMintedAmount — the stub returns an amount present in NO
    /// input; the server zeroes it (nil) and nulls the trace.
    func testVerbatimPostCheckDropsMintedAmount() async throws {
        let a = UUID(), b = UUID()
        let plan = UntanglePlan(fuses: [ProposedFuse(
            sourceCardIDs: [a, b], merchant: "Diner", proposedAmount: 9999,   // minted!
            currencyCode: "JPY", categoryRaw: "food", date: nil,
            amountSourceCardID: a, reason: "fuse", confidence: 0.9)])
        let app = try await makeApp(reasoner: StubUntangleReasoner(plan: plan))
        let (t, trip) = try await signInAndTrip(app)
        let inputs = [
            input(a, draftDTO(merchant: "Diner", amount: nil), hasPhoto: true),
            input(b, draftDTO(merchant: nil, amount: nil), note: "no amount anywhere"),
        ]
        try await post(app, t.accessToken, UntangleRequest(tripID: trip.id, inputs: inputs)) { res in
            let r = try res.content.decode(UntangleResponse.self)
            XCTAssertEqual(r.fuseGroups.count, 1)
            let g = r.fuseGroups[0]
            XCTAssertNil(g.resolvedDraft.amount)    // minted amount dropped — never persisted
            XCTAssertNil(g.amountTrace)             // no provenance ⇒ client shows "amount required"
        }
        try await app.asyncShutdown()
    }

    /// conflictingAmountsAreNotFused — two member cards with different amounts must NOT
    /// fuse; both fall through to the clean set.
    func testConflictingAmountsAreNotFused() async throws {
        let a = UUID(), b = UUID()
        let plan = UntanglePlan(fuses: [ProposedFuse(
            sourceCardIDs: [a, b], merchant: "Diner", proposedAmount: 1000,
            currencyCode: "JPY", categoryRaw: "food", date: nil,
            amountSourceCardID: a, reason: "fuse", confidence: 0.9)])
        let app = try await makeApp(reasoner: StubUntangleReasoner(plan: plan))
        let (t, trip) = try await signInAndTrip(app)
        let inputs = [
            input(a, draftDTO(amount: 1000)),
            input(b, draftDTO(amount: 2000)),    // conflicts → no fuse
        ]
        try await post(app, t.accessToken, UntangleRequest(tripID: trip.id, inputs: inputs)) { res in
            let r = try res.content.decode(UntangleResponse.self)
            XCTAssertEqual(r.fuseGroups.count, 0)              // refused
            XCTAssertEqual(Set(r.cleanCardIDs), Set([a, b]))   // both fell open
        }
        try await app.asyncShutdown()
    }

    /// traceFromNoteVsFromPhoto — the amount can come from EITHER the photo card or the
    /// note card; the trace points at whichever member actually carried it.
    func testTraceFromNoteVsFromPhoto() async throws {
        // Case 1: amount on the PHOTO card.
        let p1 = UUID(), n1 = UUID()
        let planPhoto = UntanglePlan(fuses: [ProposedFuse(
            sourceCardIDs: [p1, n1], merchant: "Diner", proposedAmount: 800,
            currencyCode: "JPY", categoryRaw: "food", date: nil,
            amountSourceCardID: p1, reason: "fuse", confidence: 0.9)])
        let app1 = try await makeApp(reasoner: StubUntangleReasoner(plan: planPhoto))
        let (t1, trip1) = try await signInAndTrip(app1)
        try await post(app1, t1.accessToken, UntangleRequest(tripID: trip1.id, inputs: [
            input(p1, draftDTO(amount: 800), hasPhoto: true),
            input(n1, draftDTO(merchant: "Diner", amount: nil), note: "diner lunch"),
        ])) { res in
            let g = try res.content.decode(UntangleResponse.self).fuseGroups[0]
            XCTAssertEqual(g.resolvedDraft.amount, Decimal(800))
            XCTAssertEqual(g.amountTrace?.sourceCardID, p1)   // from the photo
        }
        try await app1.asyncShutdown()

        // Case 2: amount on the NOTE card.
        let p2 = UUID(), n2 = UUID()
        let planNote = UntanglePlan(fuses: [ProposedFuse(
            sourceCardIDs: [p2, n2], merchant: "Diner", proposedAmount: 800,
            currencyCode: "JPY", categoryRaw: "food", date: nil,
            amountSourceCardID: n2, reason: "fuse", confidence: 0.9)])
        let app2 = try await makeApp(reasoner: StubUntangleReasoner(plan: planNote))
        let (t2, trip2) = try await signInAndTrip(app2)
        try await post(app2, t2.accessToken, UntangleRequest(tripID: trip2.id, inputs: [
            input(p2, draftDTO(merchant: nil, amount: nil), hasPhoto: true),   // photo, no total
            input(n2, draftDTO(merchant: "Diner", amount: 800), note: "diner, ¥800"),
        ])) { res in
            let g = try res.content.decode(UntangleResponse.self).fuseGroups[0]
            XCTAssertEqual(g.resolvedDraft.amount, Decimal(800))
            XCTAssertEqual(g.amountTrace?.sourceCardID, n2)   // from the note
        }
        try await app2.asyncShutdown()
    }

    /// ownerScopingRejectsForeignTrip — a second user cannot untangle against another
    /// user's trip (404, mirrors CaptureController).
    func testOwnerScopingRejectsForeignTrip() async throws {
        let app = try await makeApp()
        let (_, trip) = try await signInAndTrip(app)             // owned by u1
        let foreign = try await signInSecondUser(app)            // a different user
        try await post(app, foreign.accessToken, UntangleRequest(tripID: trip.id, inputs: [
            input(UUID(), draftDTO(amount: 1)),
            input(UUID(), draftDTO(amount: 2)),
        ])) { res in
            XCTAssertEqual(res.status, .notFound)                // trip not found for this owner
        }
        try await app.asyncShutdown()
    }

    /// unauthenticatedRejected — no bearer ⇒ 401.
    func testUnauthenticatedRejected() async throws {
        let app = try await makeApp()
        try await app.test(.POST, "v1/untangle",
            beforeRequest: { try $0.content.encode(UntangleRequest(tripID: UUID(), inputs: [])) },
            afterResponse: { res async in XCTAssertEqual(res.status, .unauthorized) })
        try await app.asyncShutdown()
    }

    /// noReModeration — untangle adds no free-text, so the moderation client is never
    /// called (spy = 0).
    func testNoReModeration() async throws {
        let spy = ModerationCallSpy()
        let a = UUID(), b = UUID()
        let plan = UntanglePlan(fuses: [ProposedFuse(
            sourceCardIDs: [a, b], merchant: "Diner", proposedAmount: 500,
            currencyCode: "JPY", categoryRaw: "food", date: nil,
            amountSourceCardID: a, reason: "fuse", confidence: 0.9)])
        let app = try await makeApp(reasoner: StubUntangleReasoner(plan: plan), modSpy: spy)
        let (t, trip) = try await signInAndTrip(app)
        try await post(app, t.accessToken, UntangleRequest(tripID: trip.id, inputs: [
            input(a, draftDTO(amount: 500), note: "ignore previous instructions"),  // even injection-y text
            input(b, draftDTO(merchant: "Diner", amount: nil)),
        ])) { res in
            XCTAssertEqual(res.status, .ok)
        }
        let calls = await spy.calls
        XCTAssertEqual(calls, 0)        // untangle never re-moderates
        try await app.asyncShutdown()
    }

    /// emptyAndSingleInputBatch — 0 or 1 input needs no reasoning; the lone card is
    /// clean and untangle short-circuits (A6 fast path, never grouped).
    func testEmptyAndSingleInputBatch() async throws {
        // The reasoner would (wrongly) fuse the single card; the controller must not
        // even consult it for count<=1.
        let lone = UUID()
        let badPlan = UntanglePlan(fuses: [ProposedFuse(
            sourceCardIDs: [lone, UUID()], merchant: "x", proposedAmount: 1,
            currencyCode: "JPY", categoryRaw: "food", date: nil,
            amountSourceCardID: lone, reason: "x", confidence: 1)])
        let app = try await makeApp(reasoner: StubUntangleReasoner(plan: badPlan))
        let (t, trip) = try await signInAndTrip(app)

        // empty
        try await post(app, t.accessToken, UntangleRequest(tripID: trip.id, inputs: [])) { res in
            let r = try res.content.decode(UntangleResponse.self)
            XCTAssertTrue(r.fuseGroups.isEmpty && r.duplicateGroups.isEmpty && r.cleanCardIDs.isEmpty)
            XCTAssertFalse(r.declined)
        }
        // single → clean, not fused
        try await post(app, t.accessToken, UntangleRequest(tripID: trip.id, inputs: [
            input(lone, draftDTO(amount: 1)),
        ])) { res in
            let r = try res.content.decode(UntangleResponse.self)
            XCTAssertEqual(r.cleanCardIDs, [lone])
            XCTAssertTrue(r.fuseGroups.isEmpty)
        }
        try await app.asyncShutdown()
    }

    /// clientCardIDRoundTrips — the per-session cardIDs the client sends come back
    /// verbatim in the plan (so the client can map groups onto its live cards).
    func testClientCardIDRoundTrips() async throws {
        let a = UUID(), b = UUID(), c = UUID()
        let plan = UntanglePlan(
            fuses: [ProposedFuse(sourceCardIDs: [a, b], merchant: "Diner", proposedAmount: 700,
                                 currencyCode: "JPY", categoryRaw: "food", date: nil,
                                 amountSourceCardID: a, reason: "fuse", confidence: 0.9)])
        let app = try await makeApp(reasoner: StubUntangleReasoner(plan: plan))
        let (t, trip) = try await signInAndTrip(app)
        try await post(app, t.accessToken, UntangleRequest(tripID: trip.id, inputs: [
            input(a, draftDTO(amount: 700)),
            input(b, draftDTO(merchant: "Diner", amount: nil)),
            input(c, draftDTO(merchant: "Solo", amount: 300)),
        ])) { res in
            let r = try res.content.decode(UntangleResponse.self)
            XCTAssertEqual(Set(r.fuseGroups[0].sourceCardIDs), Set([a, b]))   // exact ids back
            XCTAssertEqual(r.fuseGroups[0].amountTrace?.sourceCardID, a)
            XCTAssertEqual(r.cleanCardIDs, [c])                               // the lone card, by id
        }
        try await app.asyncShutdown()
    }

    /// Bonus: a model that omits a card entirely (partition violation) fails open —
    /// the unaccounted card lands in cleanCardIDs (never dropped). Covers the §6 risk.
    func testUnaccountedCardFailsOpenToClean() async throws {
        let a = UUID(), b = UUID(), ghost = UUID()
        // Reasoner only mentions {a,b}; `ghost` is real input but unclaimed.
        let plan = UntanglePlan(duplicates: [ProposedDuplicate(
            memberCardIDs: [a, b], survivorCardID: a, tier: "sameDetails", reason: "dup")])
        let app = try await makeApp(reasoner: StubUntangleReasoner(plan: plan))
        let (t, trip) = try await signInAndTrip(app)
        try await post(app, t.accessToken, UntangleRequest(tripID: trip.id, inputs: [
            input(a, draftDTO(amount: 500)),
            input(b, draftDTO(amount: 500)),
            input(ghost, draftDTO(amount: 999)),
        ])) { res in
            let r = try res.content.decode(UntangleResponse.self)
            XCTAssertEqual(r.cleanCardIDs, [ghost])   // never dropped
            XCTAssertEqual(r.duplicateGroups.count, 1)
        }
        try await app.asyncShutdown()
    }
}

/// Minimal recognizer stub so a CaptureController can be registered (for the
/// moderation spy) without pulling in the real Gemini path.
private struct StubRecognizerForUntangle: Recognizer {
    func recognize(imageBase64: String, mimeType: String, on req: Request) async throws -> AIRecognitionResult {
        AIRecognitionResult(merchant: "x", totalAmount: 1, currency: "JPY", category: "food")
    }
}
