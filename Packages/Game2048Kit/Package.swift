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
//   M3 (gameplay) — Game2048UI adds:
//     Game2048CoreKit (Game2048Engine + Game2048GameState)
//     GameAppKit (\.gameChrome environment key)
//
//   M4 (platform wiring) — this PR — adds:
//     Game2048Persistence: PersistenceKit + Telemetry (saved-game store)
//     Game2048UI adds: Game2048Persistence, MonetizationCore, MonetizationUI,
//       GameCenterKit, IssueReporting, PersistenceKit, Telemetry
//     Game2048AppComposition: full Live.swift monetization + persistence bag
//       (mirrors MinesweeperAppComposition; no audio/reminders in M4)

let productionTargets: [Target] = [
    // M4: saved-game store — maps Game2048SessionSnapshot ↔ CloudKit RecordPayload
    // via the shared public PrivateCKGateway, returning the 2048-native
    // Game2048SavedGameSummary. INERT until the user-owned ck:schema deploy adds
    // SavedGame to the tiles2048 container.
    .target(
        name: "Game2048Persistence",
        dependencies: [
            .product(name: "Game2048Engine", package: "Game2048CoreKit"),
            .product(name: "Game2048GameState", package: "Game2048CoreKit"),
            .product(name: "Persistence", package: "PersistenceKit"),
            .product(name: "Telemetry", package: "TelemetryKit"),
        ],
        swiftSettings: swiftSettings
    ),
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
            // GameAppKit: \.gameChrome EnvironmentKey (M3) + GameRootViewModel
            // typealias (M4) + GameBoardRedirect (M4 modal contract).
            .product(name: "GameAppKit", package: "GameAppKit"),
            // M4: monetization seams — BannerSlotView, RemoveAdsRow, etc.
            .product(name: "MonetizationUI", package: "AppMonetizationKit"),
            .product(name: "MonetizationCore", package: "AppMonetizationKit"),
            // M4: persistence for BoardLoaderView + GameViewModel store.
            .product(name: "Persistence", package: "PersistenceKit"),
            .product(name: "Telemetry", package: "TelemetryKit"),
            // M4: Game Center seam for daily score submit + dashboard present.
            .product(name: "GameCenterClient", package: "GameCenterKit"),
            // M4: invariant-reporting tool — reportIssue(_:) for impossible-state
            // catches (fails tests, purple-warns in #Preview, non-fatal in release).
            .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
            // M4: same-package persistence target.
            "Game2048Persistence",
        ],
        swiftSettings: swiftSettings
    ),
    .target(
        name: "Game2048AppComposition",
        dependencies: [
            "Game2048UI",
            // M4: fetchResume wiring names Game2048SavedGameStore.
            "Game2048Persistence",
            // GameAppKit: ResumeCandidate<AppRoute> + GameRootViewModel typealias.
            .product(name: "GameAppKit", package: "GameAppKit"),
            // LiveRouteFactory conforms to `RouteFactory<AppRoute>` from GameShellUI.
            .product(name: "GameShellUI", package: "GameShellKit"),
            .product(name: "Telemetry", package: "TelemetryKit"),
            // M4: full monetization + persistence bag.
            .product(name: "Persistence", package: "PersistenceKit"),
            // `.preview()` wires FakePersistence (zero-IO — mirrors MS's #261 fix).
            .product(name: "PersistenceTesting", package: "PersistenceKit"),
            .product(name: "MonetizationCore", package: "AppMonetizationKit"),
            .product(name: "MonetizationUI", package: "AppMonetizationKit"),
            .product(name: "IAPStoreKit2", package: "AppMonetizationKit"),
            .product(name: "AdsAdMob", package: "AppMonetizationKit"),
            // `.preview()` wires FakeIAPClient / FakeAdGateStateStore / FakeAdProvider.
            .product(name: "MonetizationTesting", package: "AppMonetizationKit"),
            // M4: `.live()` wires LiveGameCenterClient; `.preview()` FakeGameCenterClient.
            .product(name: "GameCenterClient", package: "GameCenterKit"),
            .product(name: "GameCenterTesting", package: "GameCenterKit"),
            // LiveRouteFactory names SettingsNoticesConfig (now in SettingsUI).
            .product(name: "SettingsUI", package: "SettingsKit"),
            // Note: no RemindersKit in M4 (2048 defers daily-ready reminder to later).
            // Note: no GameAudioKit in M4 (2048 defers audio to later milestone).
        ],
        swiftSettings: swiftSettings
    ),
]

// MARK: - Test targets

let testTargets: [Target] = [
    // M4: store tests run against the shared FakePrivateCKGateway — zero live CK.
    .testTarget(
        name: "Game2048PersistenceTests",
        dependencies: [
            "Game2048Persistence",
            .product(name: "PersistenceTesting", package: "PersistenceKit"),
            .product(name: "Game2048Engine", package: "Game2048CoreKit"),
            .product(name: "Game2048GameState", package: "Game2048CoreKit"),
        ],
        swiftSettings: swiftSettings
    ),
    // M3: Game2048UITests — ViewModel unit tests + snapshot baselines for the board.
    // Mirrors MinesweeperKit's MinesweeperUITests target shape.
    .testTarget(
        name: "Game2048UITests",
        dependencies: [
            "Game2048UI",
            "Game2048AppComposition",
            // Game2048Engine + Game2048GameState for fixture construction.
            .product(name: "Game2048Engine", package: "Game2048CoreKit"),
            .product(name: "Game2048GameState", package: "Game2048CoreKit"),
            // M3: board snapshot baselines — same precision/perceptual calibration
            // as MinesweeperUITests (0.95/0.95). macOS-only via #if canImport(AppKit).
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            // GameShellUI for theme injection in snapshot hostingView helper.
            .product(name: "GameShellUI", package: "GameShellKit"),
            // M4: fake GC + persistence for composition bootstrap tests.
            .product(name: "GameCenterClient", package: "GameCenterKit"),
            .product(name: "GameCenterTesting", package: "GameCenterKit"),
            .product(name: "PersistenceTesting", package: "PersistenceKit"),
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
        // M4: consumed by Game2048AppComposition (fetchResume wire).
        .library(name: "Game2048Persistence", targets: ["Game2048Persistence"]),
    ],
    dependencies: [
        .package(name: "GameShellKit", path: "../GameShellKit"),
        .package(name: "SettingsKit", path: "../SettingsKit"),
        .package(name: "TelemetryKit", path: "../TelemetryKit"),
        // M3: gameplay core (Foundation-only, portable).
        .package(name: "Game2048CoreKit", path: "../Game2048CoreKit"),
        // GameAppKit: GameRootViewModel typealias + GameRoot + GameBoardRedirect.
        .package(name: "GameAppKit", path: "../GameAppKit"),
        // M4: CloudKit persistence seam.
        .package(name: "PersistenceKit", path: "../PersistenceKit"),
        // M4: monetization (IAP, AdMob, MonetizationCore/UI/Testing).
        .package(name: "AppMonetizationKit", path: "../AppMonetizationKit"),
        // M4: Game Center seam.
        .package(name: "GameCenterKit", path: "../GameCenterKit"),
        // M3: snapshot test harness (macOS-only via #if canImport(AppKit)).
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
        // M4: swift-issue-reporting (IssueReporting) for invariant reporting in
        // Game2048UI. Transitive via swift-snapshot-testing; promoted to direct dep.
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.9.0"),
    ],
    targets: productionTargets + testTargets,
    swiftLanguageModes: [.v6]
)
