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
// sibling to SudokuKit and MinesweeperKit.
//
// Module names `Game2048UI` and `Game2048AppComposition` avoid the
// `SudokuUI` / `MinesweeperUI` / `AppComposition` collision that would
// otherwise occur when all packages join the same Xcode project's package
// graph.
//
// Dependency plan:
//
//   M2 (skeleton) — Game2048UI: GameShellKit, SettingsKit
//                   Game2048AppComposition: Game2048UI, GameShellKit, TelemetryKit
//
//   M3 (this PR) — Game2048UI adds:
//     Game2048CoreKit (Game2048Engine + Game2048GameState)
//     GameAppKit (\.gameChrome environment key)
//
//   M4 (platform wiring) — Game2048UI adds:
//     PersistenceKit, GameCenterKit, GameAudioKit, MonetizationCore, MonetizationUI
//     Game2048AppComposition adds the full Live.swift monetisation + persistence bag.

let productionTargets: [Target] = [
    .target(
        name: "Game2048UI",
        dependencies: [
            // GameShellKit: HomeScreen, RootShellView, RouteFactory, HomeModeItem,
            // Theme — deliberately zero-dependency shell.
            .product(name: "GameShellUI", package: "GameShellKit"),
            // SettingsUI: shared SettingsScreen wrapper.
            .product(name: "SettingsUI", package: "SettingsKit"),
            // M3: Game2048Engine (Board, Direction, Spawn, MoveEngine, Daily)
            //     + Game2048GameState (Session, Snapshot, Status).
            .product(name: "Game2048Engine", package: "Game2048CoreKit"),
            .product(name: "Game2048GameState", package: "Game2048CoreKit"),
            // M3: GameAppKit provides the `\.gameChrome` EnvironmentKey used by
            // the board view to push elapsed into the modal top chrome. No other
            // GameAppKit symbols are used at this layer — PersistenceKit /
            // GameCenterKit stay out until M4.
            .product(name: "GameAppKit", package: "GameAppKit"),
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
            // M4 will add the full Live.swift monetization + persistence bag.
            .product(name: "Telemetry", package: "TelemetryKit"),
        ],
        swiftSettings: swiftSettings
    ),
]

// MARK: - Test targets

let testTargets: [Target] = [
    // M3: Game2048UITests — ViewModel unit tests + snapshot baselines for the board.
    // Mirrors MinesweeperKit's MinesweeperUITests target shape.
    .testTarget(
        name: "Game2048UITests",
        dependencies: [
            "Game2048UI",
            // Game2048Engine + Game2048GameState for fixture construction.
            .product(name: "Game2048Engine", package: "Game2048CoreKit"),
            .product(name: "Game2048GameState", package: "Game2048CoreKit"),
            // M3: board snapshot baselines — same precision/perceptual calibration
            // as MinesweeperUITests (0.95/0.95). macOS-only via #if canImport(AppKit).
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            // GameShellUI for theme injection in snapshot hostingView helper.
            .product(name: "GameShellUI", package: "GameShellKit"),
        ],
        resources: [
            // Bundle the snapshot baselines so Xcode Cloud's distributed test
            // runner resolves them via Bundle.module (same fix as MinesweeperUITests —
            // see SnapshotConfig `SnapshotPaths`).
            .copy("__Snapshots__"),
        ],
        swiftSettings: swiftSettings
    ),
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
        .package(name: "SettingsKit", path: "../SettingsKit"),
        .package(name: "TelemetryKit", path: "../TelemetryKit"),
        // M3: gameplay core (Foundation-only, portable).
        .package(name: "Game2048CoreKit", path: "../Game2048CoreKit"),
        // M3: GameAppKit for the \.gameChrome EnvironmentKey.
        .package(name: "GameAppKit", path: "../GameAppKit"),
        // M3: snapshot test harness (macOS-only via #if canImport(AppKit)).
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    ],
    targets: productionTargets + testTargets,
    swiftLanguageModes: [.v6]
)
