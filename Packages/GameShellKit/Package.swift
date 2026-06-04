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
    .target(
        name: "GameShellUI",
        dependencies: [
            // #287 Phase 2: the reminder permission-priming UI (primer sheet +
            // `ReminderPermissionModel`) lives here as shared chrome so both
            // Sudoku and Minesweeper render an identical primer with injected
            // copy (proposal §4.4 Q2). It depends only on the
            // `NotificationAuthorizing` protocol seam from the leaf `Reminders`
            // target — never on `UserNotifications`, which stays restricted to
            // RemindersKit's Live files.
            .product(name: "Reminders", package: "RemindersKit"),
        ],
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
        dependencies: [
            "GameShellUI",
            // #287 Phase 2: `ReminderPermissionModelTests` drive the model with
            // the shared `FakeNotificationAuthorizing` fake.
            .product(name: "RemindersTesting", package: "RemindersKit"),
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
    dependencies: [
        // #287 Phase 2: RemindersKit (sibling leaf package, merged #318) hosts
        // the `NotificationAuthorizing` / `ReminderScheduler` protocol seams and
        // their Live/Noop/Fake conformers. GameShellUI consumes only the
        // `Reminders` product (protocols + value types) for the primer UI.
        .package(name: "RemindersKit", path: "../RemindersKit"),
    ],
    targets: productionTargets + testTargets,
    swiftLanguageModes: [.v6]
)
