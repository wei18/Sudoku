// swift-tools-version: 6.2

import PackageDescription

// MARK: - Shared settings

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

// MARK: - GameShellKit
//
// Game-agnostic UI shell shared across `SudokuKit`, `MinesweeperKit`, and a
// planned third game's Kit. Owns the parts of the app frame that don't change
// across games — navigation chrome, generic Settings, Daily / Practice hub
// patterns, Toast, banner ad slot — leaving each game's Kit to ship only its
// gameplay UI (BoardView, engine-facing ViewModels) and the bits that
// genuinely diverge.
//
// Extraction is incremental — see `meetings/2026-06-01_minesweeper-dev-roadmap.md`
// for the Phase X PR ordering. X1 (this) opens the package and moves
// `NavigationStackHost` over. Each subsequent X PR extracts one more piece
// while keeping Sudoku byte-identical.

let productionTargets: [Target] = [
    .target(name: "GameShellUI", swiftSettings: swiftSettings),
]

// MARK: - Package

let package = Package(
    name: "GameShellKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "GameShellUI", targets: ["GameShellUI"]),
    ],
    targets: productionTargets,
    swiftLanguageModes: [.v6]
)
