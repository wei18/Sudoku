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
// Game2048CoreKit is the pure-Swift game core for the 2048 app, sibling to
// SudokuCoreKit and MinesweeperCoreKit. Foundation-only, no SwiftUI/UIKit/
// CloudKit/GameKit imports. SDD-004 Milestone 1.
//
// Two targets mirror the MinesweeperCoreKit shape:
//
//   Game2048Engine   — board model, move engine, spawn, daily seed helper.
//                      Depends on DeterminismKit (SplitMix64) and TimeKit
//                      (UTCDay), matching the Minesweeper core's dep graph.
//                      Re-exports DeterminismKit so call sites reach SplitMix64
//                      through a single import.
//
//   Game2048GameState — Game2048Session actor + snapshot + status enum.
//                       Depends on Game2048Engine and TimeKit (MonotonicClock).
//                       Re-exports TimeKit so session consumers reach the clock
//                       protocol without an extra import.

let productionTargets: [Target] = [
    .target(
        name: "Game2048Engine",
        dependencies: [
            .product(name: "TimeKit", package: "TimeKit"),
            .product(name: "DeterminismKit", package: "DeterminismKit"),
        ],
        swiftSettings: swiftSettings
    ),
    .target(
        name: "Game2048GameState",
        dependencies: [
            "Game2048Engine",
            .product(name: "TimeKit", package: "TimeKit"),
        ],
        swiftSettings: swiftSettings
    ),
]

// MARK: - Test targets

let testTargets: [Target] = [
    .testTarget(
        name: "Game2048EngineTests",
        dependencies: [
            "Game2048Engine",
            .product(name: "TimeKit", package: "TimeKit"),
        ],
        swiftSettings: swiftSettings
    ),
    .testTarget(
        name: "Game2048GameStateTests",
        dependencies: ["Game2048GameState"],
        swiftSettings: swiftSettings
    ),
]

// MARK: - Package

let package = Package(
    name: "Game2048CoreKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "Game2048Engine", targets: ["Game2048Engine"]),
        .library(name: "Game2048GameState", targets: ["Game2048GameState"]),
    ],
    dependencies: [
        .package(path: "../TimeKit"),
        .package(path: "../DeterminismKit"),
    ],
    targets: productionTargets + testTargets,
    swiftLanguageModes: [.v6]
)
