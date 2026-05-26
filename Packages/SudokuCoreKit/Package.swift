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
// SudokuCoreKit holds the pure-Swift core extracted from SudokuKit per the
// 2026-05-26 module-split decision. Rationale: SudokuEngine + GameState only
// import `Foundation`, have no Apple-framework dependencies, and are dep'd by
// Telemetry. Hoisting them out of SudokuKit into a sibling local package
// breaks the package-level coupling that previously prevented a future
// Telemetry-only extraction. See `docs/foundations.md §2`.
//
// Dep direction (inside SudokuCoreKit):
//   SudokuEngine  ← zero external dep (Foundation only)
//   GameState     → SudokuEngine

let productionTargets: [Target] = [
    .target(name: "SudokuEngine", swiftSettings: swiftSettings),
    .target(name: "GameState", dependencies: ["SudokuEngine"], swiftSettings: swiftSettings),
]

// MARK: - Test targets

let testTargets: [Target] = [
    .testTarget(name: "SudokuEngineTests", dependencies: ["SudokuEngine"], swiftSettings: swiftSettings),
    .testTarget(name: "GameStateTests", dependencies: ["GameState", "SudokuEngine"], swiftSettings: swiftSettings),
]

// MARK: - Package

let package = Package(
    name: "SudokuCoreKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "SudokuEngine", targets: ["SudokuEngine"]),
        .library(name: "GameState", targets: ["GameState"]),
    ],
    targets: productionTargets + testTargets,
    swiftLanguageModes: [.v6]
)

// swiftlint:enable trailing_comma
