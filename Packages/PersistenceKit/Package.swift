// swift-tools-version: 6.2

import PackageDescription

// MARK: - Shared settings (foundations.md §1: Swift 6 + complete concurrency)

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

// MARK: - Production targets
//
// PersistenceKit is the fourth sibling local package extracted from SudokuKit
// (Stage 3 of the staged module split — see docs/foundations.md §2 演進).
//
// Hosts the CloudKit Private-DB persistence stack (LivePersistence,
// LivePrivateCKGateway, SavedGameStore, PersonalRecordStore,
// LiveMonetizationStateStore). Cross-platform (iOS + macOS) — CloudKit is
// available on both.
//
// Dep direction:
//   SudokuCoreKit (SudokuEngine + GameState)
//     ← TelemetryKit (Telemetry)
//     ← AppMonetizationKit (MonetizationCore — for AdGateStateStore typealias)
//     ← PersistenceKit (Persistence)

let package = Package(
    name: "PersistenceKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "PersistenceTesting", targets: ["PersistenceTesting"]),
    ],
    dependencies: [
        .package(name: "SudokuCoreKit", path: "../SudokuCoreKit"),
        .package(name: "TelemetryKit", path: "../TelemetryKit"),
        .package(name: "AppMonetizationKit", path: "../AppMonetizationKit"),
    ],
    targets: [
        .target(
            name: "Persistence",
            dependencies: [
                .product(name: "SudokuEngine", package: "SudokuCoreKit"),
                .product(name: "SudokuGameState", package: "SudokuCoreKit"),
                .product(name: "Telemetry", package: "TelemetryKit"),
                .product(name: "MonetizationCore", package: "AppMonetizationKit"),
            ],
            swiftSettings: swiftSettings
        ),
        // PersistenceTesting — FakePrivateCKGateway + PuzzleFixtures. Carved
        // out of SudokuKitTesting/Persistence/ on Stage 3 so consumers can
        // pull only the Persistence-shaped helpers.
        .target(
            name: "PersistenceTesting",
            dependencies: [
                "Persistence",
                .product(name: "SudokuEngine", package: "SudokuCoreKit"),
                .product(name: "SudokuGameState", package: "SudokuCoreKit"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: [
                "Persistence",
                "PersistenceTesting",
                .product(name: "SudokuEngine", package: "SudokuCoreKit"),
                .product(name: "SudokuGameState", package: "SudokuCoreKit"),
                .product(name: "Telemetry", package: "TelemetryKit"),
                .product(name: "TelemetryTesting", package: "TelemetryKit"),
                .product(name: "MonetizationCore", package: "AppMonetizationKit"),
                .product(name: "MonetizationTesting", package: "AppMonetizationKit"),
            ],
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
