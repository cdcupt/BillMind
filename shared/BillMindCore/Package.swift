// swift-tools-version: 6.0
import PackageDescription

// BillMindCore — the verified, Foundation-only agent core, shared by the
// Vapor server and the iOS client. No SwiftData / SwiftUI / UIKit. The same
// structs the iOS app unit-tested become the server's verification gate.
let package = Package(
    name: "BillMindCore",
    platforms: [
        .macOS(.v13),
        .iOS(.v17),
    ],
    products: [
        .library(name: "BillMindCore", targets: ["BillMindCore"]),
    ],
    targets: [
        .target(name: "BillMindCore"),
        .testTarget(
            name: "BillMindCoreTests",
            dependencies: ["BillMindCore"]
        ),
    ]
)
