import XCTVapor
import Fluent
import FluentSQLiteDriver
@testable import App

private struct StubOIDC4: OIDCVerifier {
    let identity: VerifiedIdentity
    func verify(idToken: String, provider: OIDCProvider, on req: Request) async throws -> VerifiedIdentity { identity }
}

final class SyncTests: XCTestCase {
    private func makeApp() async throws -> Application {
        let app = try await Application.make(.testing)
        app.databases.use(.sqlite(.memory), as: .sqlite)
        app.migrations.add(CreateInitialSchema())
        try await app.autoMigrate()
        app.jwt.signers.use(.hs256(key: Array("test-signing-key-0123456789abcdef".utf8)))
        let id = VerifiedIdentity(provider: .google, subject: "u1", email: "u1@example.com", isPrivateRelay: false, name: "u1")
        try app.register(collection: AuthController(oidc: StubOIDC4(identity: id)))
        try app.register(collection: TripController())
        try app.register(collection: SyncController())
        try app.register(collection: ReportController())
        return app
    }

    private func setup(_ app: Application) async throws -> (AuthTokensDTO, TripDTO) {
        var t: AuthTokensDTO!
        try await app.test(.POST, "v1/auth/google",
            beforeRequest: { try $0.content.encode(["idToken": "stub"]) },
            afterResponse: { res async throws in t = try res.content.decode(AuthTokensDTO.self) })
        var trip: TripDTO!
        try await app.test(.POST, "v1/trips", headers: ["Authorization": "Bearer \(t.accessToken)"],
            beforeRequest: { try $0.content.encode(CreateTripRequest(name: "Osaka", currencyCode: "JPY", mascot: nil)) },
            afterResponse: { res async throws in trip = try res.content.decode(TripDTO.self) })
        return (t, trip)
    }

    func testPushCreatesThenLWWUpdateThenStaleConflict() async throws {
        let app = try await makeApp()
        let (t, trip) = try await setup(app)
        let h: HTTPHeaders = ["Authorization": "Bearer \(t.accessToken)"]
        let billID = UUID()

        // create (rowVersion 1)
        try await app.test(.POST, "v1/sync", headers: h,
            beforeRequest: { try $0.content.encode(SyncPush(bills: [BillUpsert(
                id: billID, tripID: trip.id, merchant: "Ichiran", amount: 2840, currencyCode: "JPY",
                date: Date(), categoryRaw: "food", source: "text", notes: nil, rowVersion: 1, deleted: false)])) },
            afterResponse: { res async throws in
                let r = try res.content.decode(SyncPushResult.self)
                XCTAssertEqual(r.appliedBills, 1); XCTAssertTrue(r.conflicts.isEmpty)
            })

        // newer rowVersion 2 wins
        try await app.test(.POST, "v1/sync", headers: h,
            beforeRequest: { try $0.content.encode(SyncPush(bills: [BillUpsert(
                id: billID, tripID: trip.id, merchant: "Ichiran Ramen", amount: 2900, currencyCode: "JPY",
                date: Date(), categoryRaw: "food", source: "text", notes: nil, rowVersion: 2, deleted: false)])) },
            afterResponse: { res async throws in
                let r = try res.content.decode(SyncPushResult.self)
                XCTAssertEqual(r.appliedBills, 1)
            })

        // stale rowVersion 1 → conflict, not applied
        try await app.test(.POST, "v1/sync", headers: h,
            beforeRequest: { try $0.content.encode(SyncPush(bills: [BillUpsert(
                id: billID, tripID: trip.id, merchant: "stale", amount: 1, currencyCode: "JPY",
                date: Date(), categoryRaw: "food", source: "text", notes: nil, rowVersion: 1, deleted: false)])) },
            afterResponse: { res async throws in
                let r = try res.content.decode(SyncPushResult.self)
                XCTAssertEqual(r.appliedBills, 0); XCTAssertEqual(r.conflicts, [billID])
            })

        let bill = try await Bill.find(billID, on: app.db)
        XCTAssertEqual(bill?.merchant, "Ichiran Ramen")  // the v2 write stuck
        XCTAssertEqual(bill?.amount, Decimal(2900))
        try await app.asyncShutdown()
    }

    func testPullReturnsDeltaAndTombstones() async throws {
        let app = try await makeApp()
        let (t, trip) = try await setup(app)
        let h: HTTPHeaders = ["Authorization": "Bearer \(t.accessToken)"]
        let billID = UUID()
        try await app.test(.POST, "v1/sync", headers: h,
            beforeRequest: { try $0.content.encode(SyncPush(bills: [BillUpsert(
                id: billID, tripID: trip.id, merchant: "Ichiran", amount: 2840, currencyCode: "JPY",
                date: Date(), categoryRaw: "food", source: "text", notes: nil, rowVersion: 1, deleted: false)])) },
            afterResponse: { res async in XCTAssertEqual(res.status, .ok) })

        // full pull (since 0) sees the trip + bill
        try await app.test(.GET, "v1/sync?since=0", headers: h, afterResponse: { res async throws in
            let delta = try res.content.decode(SyncDelta.self)
            XCTAssertEqual(delta.trips.count, 1)
            XCTAssertEqual(delta.bills.count, 1)
            XCTAssertFalse(delta.bills.first?.deleted ?? true)
        })

        // delete via push (tombstone)
        try await app.test(.POST, "v1/sync", headers: h,
            beforeRequest: { try $0.content.encode(SyncPush(bills: [BillUpsert(
                id: billID, tripID: trip.id, merchant: "Ichiran", amount: 2840, currencyCode: "JPY",
                date: Date(), categoryRaw: "food", source: "text", notes: nil, rowVersion: 2, deleted: true)])) },
            afterResponse: { res async in XCTAssertEqual(res.status, .ok) })

        try await app.test(.GET, "v1/sync?since=0", headers: h, afterResponse: { res async throws in
            let delta = try res.content.decode(SyncDelta.self)
            XCTAssertEqual(delta.bills.count, 1)
            XCTAssertTrue(delta.bills.first?.deleted ?? false)   // tombstone propagates
        })
        try await app.asyncShutdown()
    }

    func testReportCreatesRow() async throws {
        let app = try await makeApp()
        let (t, _) = try await setup(app)
        try await app.test(.POST, "v1/moderation/report", headers: ["Authorization": "Bearer \(t.accessToken)"],
            beforeRequest: { try $0.content.encode(ReportController.ReportRequest(
                messageID: UUID(), sessionID: nil, tripID: nil, reason: "Harmful or unsafe", note: "x")) },
            afterResponse: { res async throws in
                XCTAssertEqual(res.status, .accepted)
                let r = try res.content.decode(ReportController.ReportResponse.self)
                XCTAssertNotNil(r.reportID)
            })
        let count = try await ContentReport.query(on: app.db).count()
        XCTAssertEqual(count, 1)
        try await app.asyncShutdown()
    }
}
