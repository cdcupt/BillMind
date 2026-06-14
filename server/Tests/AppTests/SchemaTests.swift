import XCTVapor
import Fluent
import FluentSQLiteDriver
@testable import App

/// Verifies the initial migration actually runs and the ownership chain
/// (user → trip → bill → line item) persists, with money round-tripping as
/// exact Decimal. Runs on in-memory SQLite so it needs no Docker/Postgres.
final class SchemaTests: XCTestCase {
    private func makeApp() async throws -> Application {
        let app = try await Application.make(.testing)
        app.databases.use(.sqlite(.memory), as: .sqlite)
        app.migrations.add(CreateInitialSchema())
        try await app.autoMigrate()
        return app
    }

    func testMigrationAndOwnershipChainRoundTrip() async throws {
        let app = try await makeApp()

        let user = User(displayName: "Erik")
        try await user.save(on: app.db)

        let trip = Trip(ownerID: try user.requireID(), name: "Osaka", currencyCode: "JPY")
        try await trip.save(on: app.db)

        let bill = Bill(
            tripID: try trip.requireID(), merchant: "Ichiran",
            amount: Decimal(string: "2840.00")!, currencyCode: "JPY",
            date: Date(), categoryRaw: "food", source: "text",
            createdByID: try user.requireID()
        )
        try await bill.save(on: app.db)

        let item = LineItem(billID: try bill.requireID(), label: "Ramen",
                            amount: Decimal(string: "2840.00")!, sortIndex: 0)
        try await item.save(on: app.db)

        // Read it back through the relation and assert money is exact.
        let fetched = try await Bill.find(bill.id, on: app.db)
        XCTAssertEqual(fetched?.merchant, "Ichiran")
        XCTAssertEqual(fetched?.amount, Decimal(string: "2840.00"))
        XCTAssertEqual(fetched?.$trip.id, trip.id)

        let items = try await LineItem.query(on: app.db)
            .filter(\.$bill.$id == (try bill.requireID())).all()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.amount, Decimal(string: "2840.00"))

        try await app.asyncShutdown()
    }

    func testIdentityUniquenessAcrossProviders() async throws {
        let app = try await makeApp()

        let user = try await {
            let u = User(displayName: "Erik"); try await u.save(on: app.db); return u
        }()
        let apple = Identity(userID: try user.requireID(), provider: "apple",
                             subject: "apple-sub-1", isPrivateRelay: true)
        try await apple.save(on: app.db)
        let google = Identity(userID: try user.requireID(), provider: "google",
                              subject: "apple-sub-1", isPrivateRelay: false)
        // Same subject string but different provider must be allowed.
        try await google.save(on: app.db)

        let count = try await Identity.query(on: app.db).count()
        XCTAssertEqual(count, 2)

        try await app.asyncShutdown()
    }
}
