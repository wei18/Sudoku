// swift-tools-version: 6.2

import PackageDescription

// MARK: - Shared settings

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

// MARK: - Production targets
//
// Game2048Kit is the UI + composition shell for the Tiles2048 app target,
// sibling to SudokuKit and MinesweeperKit. SDD-004 Milestone 2 is a
// skeleton-only shell so `Project.swift`'s Tiles2048 target links a real
// product and `tuist generate` produces the Tiles2048 scheme. Real gameplay
// UI (BoardView, gestures, animation) and full platform wiring land in
// Milestones 3–4.
//
// Module names `Game2048UI` and `Game2048AppComposition` avoid the
// `SudokuUI` / `MinesweeperUI` / `AppComposition` collision that would
// otherwise occur when all packages join the same Xcode project's package
// graph.
//
// Dependency plan:
//
//   M2 (this PR) — skeleton UI + composition root:
//     Game2048UI:           GameShellKit (HomeScreen stub), SettingsKit
//     Game2048AppComposition: Game2048UI, GameShellKit, TelemetryKit
//
//   M3 (gameplay UI) — add to Game2048UI:
//     Game2048CoreKit (Game2048Engine + Game2048GameState)
//     GameAppKit (GameRootViewModel<AppRoute> typealias)
//     PersistenceKit, TelemetryKit, GameCenterKit
//     IssueReporting (xctest-dynamic-overlay)
//     GameAudioKit
//
//   M3 (gameplay) — add to Game2048AppComposition:
//     Game2048CoreKit, GameAppKit
//     PersistenceKit, PersistenceTesting (preview bag)
//     MonetizationCore, MonetizationUI, IAPStoreKit2, AdsAdMob, MonetizationTesting
//     GameCenterKit, GameCenterTesting
//     RemindersKit, GameAudioKit
//
//   M4 (platform wiring) — snapshot test targets, AppInfo.plist fixture,
//     MinesweeperUITests-style CR suite, Game2048Persistence target mirror.

let productionTargets: [Target] = [
    .target(
        name: "Game2048UI",
        dependencies: [
            // GameShellKit: HomeScreen, RootShellView, RouteFactory, HomeModeItem,
            // Theme — the shell is deliberately zero-dependency so this target
            // stays importable without any seam (Persistence/GC/Telemetry) dep.
            // M3 will add Game2048CoreKit + GameAppKit + the seam products.
            .product(name: "GameShellUI", package: "GameShellKit"),
            // SettingsUI: shared SettingsScreen wrapper; the 2048 SettingsView
            // will mirror MinesweeperKit's SettingsView once M3 wires it.
            .product(name: "SettingsUI", package: "SettingsKit"),
        ],
        swiftSettings: swiftSettings
    ),
    .target(
        name: "Game2048AppComposition",
        dependencies: [
            "Game2048UI",
            // GameShellUI: RouteFactory<AppRoute> conformance.
            .product(name: "GameShellUI", package: "GameShellKit"),
            // Telemetry + ErrorReporter seam — mirrors MS AppComposition shape.
            // M3 will add the full Live.swift monetization + persistence bag.
            .product(name: "Telemetry", package: "TelemetryKit"),
        ],
        swiftSettings: swiftSettings
    ),
]

let testTargets: [Target] = [
    // M3/M4: Add Game2048UITests here (snapshot + composition smoke tests),
    // mirroring MinesweeperKit's MinesweeperUITests shape.
    // Stub test target intentionally omitted in M2 — there is no non-trivial
    // surface to test yet; the build itself is the M2 verification criterion.
]

// MARK: - Package

let package = Package(
    name: "Game2048Kit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "Game2048UI", targets: ["Game2048UI"]),
        .library(name: "Game2048AppComposition", targets: ["Game2048AppComposition"]),
    ],
    dependencies: [
        .package(name: "GameShellKit", path: "../GameShellKit"),
        // refactor/settingskit-target parity: shared Settings screen + reminders UI.
        .package(name: "SettingsKit", path: "../SettingsKit"),
        // M3: add Game2048CoreKit, GameAppKit, TelemetryKit, PersistenceKit,
        //     AppMonetizationKit, GameCenterKit, RemindersKit, GameAudioKit,
        //     swift-snapshot-testing, xctest-dynamic-overlay when gameplay lands.
        .package(name: "TelemetryKit", path: "../TelemetryKit"),
    ],
    targets: productionTargets + testTargets,
    swiftLanguageModes: [.v6]
)
