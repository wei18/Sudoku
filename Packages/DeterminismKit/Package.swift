// swift-tools-version: 6.2

import PackageDescription

// MARK: - Shared settings (foundations.md §1: Swift 6 + complete concurrency)

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

// MARK: - DeterminismKit
//
// Tiny game-agnostic leaf holding the shared seeded-RNG primitives (#446):
// the `DeterministicRNG` value-type protocol (with `nextInt(upperBound:)`
// rejection sampling + `shuffleInPlace` Fisher–Yates) and the `SplitMix64`
// generator. Previously `SplitMix64` + `DeterministicRNG` lived in
// `SudokuEngine` and were byte-mirrored (and had DIVERGED) into
// `MinesweeperEngine`. The RNG drives puzzle/board generation, so the merged
// code is bit-identical to the Sudoku original. Hoisting it into this true
// leaf — which depends on nothing and is depended on by BOTH game cores —
// removes the duplication while keeping the dependency graph flowing upward
// (DeterminismKit ← SudokuEngine / MinesweeperEngine).
//
// Dep direction: DeterminismKit ← (Foundation-free, zero external dep).

let productionTargets: [Target] = [
    .target(name: "DeterminismKit", swiftSettings: swiftSettings),
]

// MARK: - Test targets

let testTargets: [Target] = [
    .testTarget(name: "DeterminismKitTests", dependencies: ["DeterminismKit"], swiftSettings: swiftSettings),
]

// MARK: - Package

let package = Package(
    name: "DeterminismKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "DeterminismKit", targets: ["DeterminismKit"]),
    ],
    targets: productionTargets + testTargets,
    swiftLanguageModes: [.v6]
)
