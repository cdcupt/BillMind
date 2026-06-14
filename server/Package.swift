// swift-tools-version: 6.0
import PackageDescription

// BillMind 2.0 server — Vapor + Fluent/Postgres, importing the shared
// BillMindCore (the verified agent core, used verbatim as the server's
// verification gate). Built as a single static binary for the VPS.
let package = Package(
    name: "server",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../shared/BillMindCore"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.9.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.8.0"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "BillMindCore", package: "BillMindCore"),
            ],
            // Vapor/Fluent are battle-tested under the Swift 5 language mode;
            // the shared core stays Swift 6. Keeps the first build clean.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
