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
// MinesweeperCoreKit is the pure-Swift game core for the Minesweeper app,
// siblings to SudokuCoreKit. PR D scope is skeleton-only — `MinesweeperEngine`
// ships as a placeholder type so `Project.swift`'s second target compiles and
// `tuist generate` produces both schemes. Real engine work (mine placement,
// reveal flood-fill, win/lose detection) lands in a follow-up.
//
// Module name `MinesweeperEngine` avoids the `GameState` collision that would
// occur if a second SwiftPM target with that name joined the same Xcode
// project alongside SudokuCoreKit's `GameState`. A separate Minesweeper
// `GameState` module can be added later under a namespaced name when needed.

let productionTargets: [Target] = [
    // MinesweeperEngine depends on the shared `TimeKit` leaf for `UTCDay`
    // (#305) — previously byte-mirrored in-package (#290), now imported from
    // the game-agnostic leaf both cores share — and on the shared
    // `DeterminismKit` leaf for `SplitMix64` / `DeterministicRNG` (#446),
    // previously a diverged in-package copy. It re-exports DeterminismKit so
    // existing `import MinesweeperEngine` call sites reach `SplitMix64`
    // unchanged.
    .target(
        name: "MinesweeperEngine",
        dependencies: [
            .product(name: "TimeKit", package: "TimeKit"),
            .product(name: "DeterminismKit", package: "DeterminismKit"),
        ],
        swiftSettings: swiftSettings
    ),
    // MinesweeperGameState depends on the shared `TimeKit` leaf for
    // `MonotonicClock` / `LiveMonotonicClock` (#446), previously an in-package
    // copy. It re-exports TimeKit so `import MinesweeperGameState` call sites
    // reach the clock unchanged.
    .target(
        name: "MinesweeperGameState",
        dependencies: [
            "MinesweeperEngine",
            .product(name: "TimeKit", package: "TimeKit"),
        ],
        swiftSettings: swiftSettings
    ),
]

// MARK: - Test targets

let testTargets: [Target] = [
    .testTarget(
        name: "MinesweeperEngineTests",
        dependencies: [
            "MinesweeperEngine",
            // `UTCDay` assertions reach the shared TimeKit leaf directly (#305).
            .product(name: "TimeKit", package: "TimeKit"),
        ],
        swiftSettings: swiftSettings
    ),
    .testTarget(
        name: "MinesweeperGameStateTests",
        dependencies: ["MinesweeperGameState"],
        swiftSettings: swiftSettings
    ),
]

// MARK: - Package

let package = Package(
    name: "MinesweeperCoreKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "MinesweeperEngine", targets: ["MinesweeperEngine"]),
        .library(name: "MinesweeperGameState", targets: ["MinesweeperGameState"]),
    ],
    dependencies: [
        .package(path: "../TimeKit"),
        .package(path: "../DeterminismKit"),
    ],
    targets: productionTargets + testTargets,
    swiftLanguageModes: [.v6]
)
