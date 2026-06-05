// swift-tools-version: 6.2

import PackageDescription

// MARK: - Shared settings (foundations.md §1: Swift 6 + complete concurrency)

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

// MARK: - TimeKit
//
// Tiny game-agnostic leaf holding the shared `UTCDay` calendar-day formatter
// (#305). Previously `UTCDay` lived in `SudokuEngine` and was byte-mirrored
// into `MinesweeperEngine` (#290) to avoid a wrong-direction MS→Sudoku core
// coupling. Hoisting it into this true leaf — which depends on nothing and is
// depended on by BOTH game cores — removes the duplication while keeping the
// dependency graph flowing upward (TimeKit ← SudokuEngine / MinesweeperEngine).
//
// Dep direction: TimeKit ← (Foundation only, zero external dep).

let productionTargets: [Target] = [
    .target(name: "TimeKit", swiftSettings: swiftSettings),
]

// MARK: - Test targets

let testTargets: [Target] = [
    .testTarget(name: "TimeKitTests", dependencies: ["TimeKit"], swiftSettings: swiftSettings),
]

// MARK: - Package

let package = Package(
    name: "TimeKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "TimeKit", targets: ["TimeKit"]),
    ],
    targets: productionTargets + testTargets,
    swiftLanguageModes: [.v6]
)
