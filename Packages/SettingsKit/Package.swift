// swift-tools-version: 6.2

import PackageDescription

// MARK: - Shared settings

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

// MARK: - SettingsKit
//
// Shared Settings UI carved out of `GameShellKit/Sources/GameShellUI/`. Owns the
// game-agnostic Settings *page* (`SettingsScreen` assembly + `SettingsShellView`
// Form chrome + the About/Storage/Notices building blocks) AND the reminders UI
// (the `ReminderSettingsSection` + its `ReminderSettingsModel`, the soft pre-ask
// `ReminderPrimerSheet` + `ReminderDeniedExplainer`, and the
// `ReminderPermissionModel` that drives the system prompt). Both Sudoku and
// Minesweeper mount the identical screen + reminders section with copy/config
// INJECTED at their composition roots.
//
// Dependency edge (impl-notes 2026-06-09 D1):
//   - GameShellUI — the primer/denied sheets read `@Environment(\.theme)` and
//     fall back to GameShellUI's `NeutralTheme`. GameShellUI must NOT depend
//     back on SettingsUI (verified: no production reference remains), so the
//     SettingsUI → GameShellUI edge is a clean DAG, no cycle.
//   - Reminders — the protocol seams the models re-export (`ReminderAuthStatus`,
//     `NotificationAuthorizing`, `ReminderScheduler`, `ReminderKind`,
//     `ReminderContent`). Never `UserNotifications` (that stays in RemindersKit's
//     Live files).
//
// SettingsUI must NOT import MonetizationUI / GameCenter / IAP / AdMob — the
// Purchases section stays an injected `@ViewBuilder` slot supplied by each app's
// wrapper. The `SettingsUITests` purchases-slot sentinel pins that boundary.

let productionTargets: [Target] = [
    .target(
        name: "SettingsUI",
        dependencies: [
            .product(name: "GameShellUI", package: "GameShellKit"),
            .product(name: "Reminders", package: "RemindersKit"),
            .product(name: "GameAudio", package: "GameAudioKit"),
            // #556 SDD-005 Pillar B: `ReminderPrimerCoordinator` moved here from
            // SudokuUI so GameAppKit can reference it in `GameDeps` without a
            // module cycle. The coordinator emits `TelemetryEvent` via an injected
            // closure — this dep is for the `TelemetryEvent` value type only.
            .product(name: "Telemetry", package: "TelemetryKit"),
        ],
        swiftSettings: swiftSettings
    ),
]

// MARK: - Test targets

let testTargets: [Target] = [
    .testTarget(
        name: "SettingsUITests",
        dependencies: [
            "SettingsUI",
            // The moved `ReminderSettingsModelTests` / `ReminderPermissionModelTests`
            // drive the models with the shared Noop/Fake authorizers.
            .product(name: "RemindersTesting", package: "RemindersKit"),
            // `AudioSettingsModelTests` drives the audio model with the shared
            // Fake sound player to assert setters push to the live player.
            .product(name: "GameAudioTesting", package: "GameAudioKit"),
        ],
        swiftSettings: swiftSettings
    ),
]

// MARK: - Package

let package = Package(
    name: "SettingsKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "SettingsUI", targets: ["SettingsUI"]),
    ],
    dependencies: [
        .package(name: "GameShellKit", path: "../GameShellKit"),
        .package(name: "RemindersKit", path: "../RemindersKit"),
        .package(name: "GameAudioKit", path: "../GameAudioKit"),
        // #556 SDD-005 Pillar B: `ReminderPrimerCoordinator` moved here; it emits
        // `TelemetryEvent` via an injected closure — TelemetryKit for the type only.
        .package(name: "TelemetryKit", path: "../TelemetryKit"),
    ],
    targets: productionTargets + testTargets,
    swiftLanguageModes: [.v6]
)
