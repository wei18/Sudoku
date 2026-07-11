// swift-tools-version: 6.2

import PackageDescription

// MARK: - Shared settings (foundations.md §1: Swift 6 + complete concurrency)

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

// MARK: - GameTestSupportKit
//
// #750: extracted from the byte-drifted SudokuUITests/MinesweeperUITests copies
// of ASCScreenshotRender.swift (see #713 upkeep finding). Test-only rendering
// machinery for App Store Connect screenshot emission — AppKit/SwiftUI only,
// zero dependency on any other Kit, so it is wired into SudokuKit /
// MinesweeperKit exclusively via their *UITests target dependency lists, never
// a production target. That keeps it out of the shipped app binaries while
// still letting both apps consume one implementation instead of forking it.
//
// Per-app difference (the `@testable import SudokuUI` / `MinesweeperUI`) never
// belonged to this file: nothing in it names a Sudoku/Minesweeper-specific
// type — it is generic over `V: SwiftUI.View` and only calls the per-target
// `hostingView(...)` helper (still defined per-app in SnapshotConfig.swift,
// since the size-class/theme wiring hostingView performs IS the per-app seam).

let productionTargets: [Target] = [
    .target(name: "GameTestSupportKit", swiftSettings: swiftSettings),
]

// MARK: - Test targets

let testTargets: [Target] = [
    .testTarget(
        name: "GameTestSupportKitTests",
        dependencies: ["GameTestSupportKit"],
        swiftSettings: swiftSettings
    ),
]

// MARK: - Package

let package = Package(
    name: "GameTestSupportKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "GameTestSupportKit", targets: ["GameTestSupportKit"]),
    ],
    targets: productionTargets + testTargets,
    swiftLanguageModes: [.v6]
)
