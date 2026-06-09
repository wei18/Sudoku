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
// SudokuCoreKit holds the pure-Swift core extracted from SudokuKit per the
// 2026-05-26 module-split decision. Rationale: SudokuEngine + GameState only
// import `Foundation`, have no Apple-framework dependencies, and are dep'd by
// Telemetry. Hoisting them out of SudokuKit into a sibling local package
// breaks the package-level coupling that previously prevented a future
// Telemetry-only extraction. See `docs/foundations.md §2`.
//
// Dep direction (inside SudokuCoreKit):
//   SudokuEngine  → TimeKit (shared UTCDay leaf, #305),
//                   DeterminismKit (shared SplitMix64/DeterministicRNG, #446)
//   GameState     → SudokuEngine, TimeKit (shared MonotonicClock leaf, #446)
//
// SudokuEngine re-exports TimeKit's `UTCDay` and DeterminismKit's
// `SplitMix64`/`DeterministicRNG` (`@_exported import`) so existing consumers
// that `import SudokuEngine` keep reaching those symbols unchanged after the
// #305 / #446 extractions. GameState re-exports TimeKit's `MonotonicClock`
// for the same reason (#446).

let productionTargets: [Target] = [
    .target(
        name: "SudokuEngine",
        dependencies: [
            .product(name: "TimeKit", package: "TimeKit"),
            .product(name: "DeterminismKit", package: "DeterminismKit"),
        ],
        swiftSettings: swiftSettings
    ),
    .target(
        name: "GameState",
        dependencies: [
            "SudokuEngine",
            .product(name: "TimeKit", package: "TimeKit"),
        ],
        swiftSettings: swiftSettings
    ),
]

// MARK: - Test targets

let testTargets: [Target] = [
    .testTarget(name: "SudokuEngineTests", dependencies: ["SudokuEngine"], swiftSettings: swiftSettings),
    // SudokuEngine pulled in transitively via GameState — no need to list explicitly.
    .testTarget(name: "GameStateTests", dependencies: ["GameState"], swiftSettings: swiftSettings),
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
    dependencies: [
        .package(path: "../TimeKit"),
        .package(path: "../DeterminismKit"),
    ],
    targets: productionTargets + testTargets,
    swiftLanguageModes: [.v6]
)
