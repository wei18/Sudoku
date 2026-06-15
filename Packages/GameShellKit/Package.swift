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
// Extraction is incremental, in `Phase X` PRs: X1 (this) opens the package and
// moves `NavigationStackHost` over. Each subsequent X PR extracts one more piece
// while keeping Sudoku byte-identical.

let productionTargets: [Target] = [
    .target(
        name: "GameShellUI",
        // The reminder permission-priming UI (primer sheet + the reminder
        // models) and the shared Settings screen moved to the sibling
        // `SettingsKit` package (refactor/settingskit-target, 2026-06-09).
        // GameShellUI now owns only the game-agnostic shell chrome
        // (navigation host, hub shells, Theme) and no longer depends on the
        // `Reminders` seam — SettingsKit consumes it directly.
        swiftSettings: swiftSettings
    ),
]

// MARK: - Test targets
//
// `GameShellUITests` carries the X1 sentinel: a compile-only `@Test` that
// instantiates `NavigationStackHost` with a non-Sudoku `Route` type. If a
// future refactor accidentally re-couples the host to a specific Route, this
// target stops compiling.

let testTargets: [Target] = [
    .testTarget(
        name: "GameShellUITests",
        // The reminder/settings model tests moved to `SettingsKit`'s
        // `SettingsUITests` (refactor/settingskit-target, 2026-06-09), so this
        // target no longer needs `RemindersTesting`.
        dependencies: [
            "GameShellUI",
        ],
        swiftSettings: swiftSettings
    ),
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
    dependencies: [],
    targets: productionTargets + testTargets,
    swiftLanguageModes: [.v6]
)
