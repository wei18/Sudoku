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
    .target(name: "MinesweeperEngine", swiftSettings: swiftSettings),
    .target(
        name: "MinesweeperGameState",
        dependencies: ["MinesweeperEngine"],
        swiftSettings: swiftSettings
    ),
]

// MARK: - Test targets

let testTargets: [Target] = [
    .testTarget(name: "MinesweeperEngineTests", dependencies: ["MinesweeperEngine"], swiftSettings: swiftSettings),
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
    targets: productionTargets + testTargets,
    swiftLanguageModes: [.v6]
)
