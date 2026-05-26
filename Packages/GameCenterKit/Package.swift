// swift-tools-version: 6.2

// swiftlint:disable trailing_comma

import PackageDescription

// MARK: - Shared settings (foundations.md §1: Swift 6 + complete concurrency)

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

// MARK: - Production targets
//
// GameCenterKit is the fifth sibling local package extracted from SudokuKit
// (Stage 3 of the staged module split — see docs/foundations.md §2 演進).
//
// Hosts the Game Center seam (LiveGameCenterClient, GKAuthDriver,
// GKLeaderboardLoader, AchievementEvaluator, GameCenterSink). GameKit is
// guarded inside `Sources/.../Live/*.swift` via `#if canImport(GameKit)`,
// so the target compiles cross-platform (iOS + macOS); the SPM target
// itself stays unconditional.
//
// Dep direction:
//   SudokuCoreKit (SudokuEngine)
//     ← TelemetryKit (Telemetry)
//     ← PersistenceKit (Persistence — for PersonalRecord / leaderboard plumbing)
//     ← GameCenterKit (GameCenterClient)

let package = Package(
    name: "GameCenterKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "GameCenterClient", targets: ["GameCenterClient"]),
        .library(name: "GameCenterTesting", targets: ["GameCenterTesting"]),
    ],
    dependencies: [
        .package(name: "SudokuCoreKit", path: "../SudokuCoreKit"),
        .package(name: "TelemetryKit", path: "../TelemetryKit"),
        .package(name: "PersistenceKit", path: "../PersistenceKit"),
    ],
    targets: [
        .target(
            name: "GameCenterClient",
            dependencies: [
                .product(name: "SudokuEngine", package: "SudokuCoreKit"),
                .product(name: "Telemetry", package: "TelemetryKit"),
                .product(name: "Persistence", package: "PersistenceKit"),
            ],
            swiftSettings: swiftSettings
        ),
        // GameCenterTesting — FakeGameCenterClient + FakeLeaderboardLoader +
        // FakeAuthDriver. Carved out of SudokuKitTesting/GameCenter/ on
        // Stage 3 so consumers can pull only the GameCenter-shaped helpers.
        .target(
            name: "GameCenterTesting",
            dependencies: [
                "GameCenterClient",
                .product(name: "SudokuEngine", package: "SudokuCoreKit"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "GameCenterClientTests",
            dependencies: [
                "GameCenterClient",
                "GameCenterTesting",
                .product(name: "SudokuEngine", package: "SudokuCoreKit"),
                .product(name: "GameState", package: "SudokuCoreKit"),
                .product(name: "Telemetry", package: "TelemetryKit"),
                .product(name: "Persistence", package: "PersistenceKit"),
            ],
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)

// swiftlint:enable trailing_comma
