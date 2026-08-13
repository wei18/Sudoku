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
// GameCenterKit is the fifth sibling local package extracted from SudokuKit
// (Stage 3 of the staged module split — see docs/foundations.md §2 演進).
//
// Hosts the Game Center seam (LiveGameCenterClient, GKAuthDriver).
// GameKit is guarded inside `Sources/.../Live/*.swift`
// via `#if canImport(GameKit)`, so the target compiles cross-platform
// (iOS + macOS); the SPM target itself stays unconditional.
//
// #955: AchievementEvaluator, GameCenterSink, and SubmitGuards moved to
// SudokuKit/Sources/SudokuAppComposition/GameCenter/ — they were Sudoku-
// specific (concrete SudokuEngine.Difficulty in their public API, a
// PersistenceKit dependency only they used), not part of the game-agnostic
// seam. GameCenterKit keeps its SudokuCoreKit dependency: LeaderboardIDs.swift
// still needs SudokuEngine.Difficulty for the leaderboard-id mapping (a
// requirement of the GameCenterClient protocol itself), so this is a
// narrowing, not a full decoupling.
//
// Dep direction:
//   SudokuCoreKit (SudokuEngine)
//     ← TelemetryKit (Telemetry)
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
    ],
    targets: [
        .target(
            name: "GameCenterClient",
            dependencies: [
                .product(name: "SudokuEngine", package: "SudokuCoreKit"),
                .product(name: "Telemetry", package: "TelemetryKit"),
            ],
            swiftSettings: swiftSettings
        ),
        // GameCenterTesting — FakeGameCenterClient + FakeAuthDriver. Carved
        // out of SudokuKitTesting/GameCenter/ on Stage 3 so consumers can
        // pull only the GameCenter-shaped helpers.
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
                .product(name: "Telemetry", package: "TelemetryKit"),
            ],
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
