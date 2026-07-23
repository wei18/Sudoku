// swift-tools-version: 6.2

import PackageDescription

// MARK: - Shared settings (foundations.md §1: Swift 6 + complete concurrency)

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

// MARK: - GameAppKit
//
// Game-agnostic *app-level* shell that sits ABOVE GameShellUI (#448 step 1a).
//
// GameShellKit is deliberately zero-dependency — it owns only the pure UI
// chrome (navigation host, hub shells, Theme) and must NOT import
// Persistence / GameCenter / Telemetry. The generic app-launch coordinator
// (`GameRootViewModel<Route>`) needs all three, so it goes HERE instead:
//
//   GameShellUI (zero-dep UI)  ←  GameAppKit (app coordination + the deps)
//
// Both Sudoku and Minesweeper depend on this for their Root VM. Step 1a
// migrates Sudoku only; Minesweeper migration is step 1b.
//
// Dep direction:
//   GameCenterKit / PersistenceKit / TelemetryKit  ←  GameAppKit

let productionTargets: [Target] = [
    .target(
        name: "GameAppKit",
        dependencies: [
            .product(name: "GameCenterClient", package: "GameCenterKit"),
            .product(name: "Persistence", package: "PersistenceKit"),
            .product(name: "Telemetry", package: "TelemetryKit"),
            // #448 step 3: shared `GameRoot` view + `ResumePill`. GameShellUI
            // for the `RootShellView` / `SidebarItem` / `RouteFactory` shell +
            // the `Theme` environment; MonetizationUI for `ToastController` +
            // the `.toastOverlay(…)` helper. (GameShellKit stays zero-dep — the
            // deps live here, above it.)
            .product(name: "GameShellUI", package: "GameShellKit"),
            .product(name: "MonetizationUI", package: "AppMonetizationKit"),
            // #556 SDD-005 Pillar B: `makeGameApp(config:)` wires the full live stack.
            // MonetizationCore for AdGate/AdProvider/IAPClient seams (MonetizationUI
            // re-exports ToastController + the `ATTPrimerCoordinator` moved there in
            // #556; MonetizationCore for AdGate itself). AdsAdMob for
            // LiveAdMobAdProvider + ATTPresenter. IAPStoreKit2 for
            // LiveStoreKit2IAPClient. GameAudio for the audio stack. SettingsUI for
            // ReminderPrimerCoordinator + ReminderSettingsEntry (moved there in
            // #556) + AudioSettingsModel.
            .product(name: "MonetizationCore", package: "AppMonetizationKit"),
            .product(name: "AdsAdMob", package: "AppMonetizationKit"),
            .product(name: "IAPStoreKit2", package: "AppMonetizationKit"),
            .product(name: "GameAudio", package: "GameAudioKit"),
            .product(name: "SettingsUI", package: "SettingsKit"),
            .product(name: "Reminders", package: "RemindersKit"),
            // #935 batch 4: SudokuEngine for the `Difficulty` type needed by
            // `UITestSignedOutGameCenterClient`'s `GameCenterClient`
            // conformance (`submitScore(puzzleId:...difficulty:...)`).
            .product(name: "SudokuEngine", package: "SudokuCoreKit"),
        ],
        swiftSettings: swiftSettings
    ),
]

// MARK: - Test targets

let testTargets: [Target] = [
    .testTarget(
        name: "GameAppKitTests",
        dependencies: [
            "GameAppKit",
            .product(name: "GameCenterClient", package: "GameCenterKit"),
            .product(name: "Persistence", package: "PersistenceKit"),
            .product(name: "Telemetry", package: "TelemetryKit"),
            // SudokuEngine for the `Mode` / `Difficulty` value types needed to
            // construct a `SavedGameSummary` fixture; GameState for
            // `GameSessionSnapshot` in the inline `PersistenceProtocol` stub.
            .product(name: "SudokuEngine", package: "SudokuCoreKit"),
            .product(name: "SudokuGameState", package: "SudokuCoreKit"),
        ],
        swiftSettings: swiftSettings
    ),
]

// MARK: - Package

let package = Package(
    name: "GameAppKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "GameAppKit", targets: ["GameAppKit"]),
    ],
    dependencies: [
        .package(name: "GameCenterKit", path: "../GameCenterKit"),
        .package(name: "PersistenceKit", path: "../PersistenceKit"),
        .package(name: "TelemetryKit", path: "../TelemetryKit"),
        .package(name: "SudokuCoreKit", path: "../SudokuCoreKit"),
        // #448 step 3: shared `GameRoot` view + `ResumePill` consume the
        // zero-dep UI shell + the monetization toast overlay.
        .package(name: "GameShellKit", path: "../GameShellKit"),
        .package(name: "AppMonetizationKit", path: "../AppMonetizationKit"),
        // #556 SDD-005 Pillar B: `makeGameApp(config:)` wires the full live stack.
        .package(name: "GameAudioKit", path: "../GameAudioKit"),
        .package(name: "SettingsKit", path: "../SettingsKit"),
        .package(name: "RemindersKit", path: "../RemindersKit"),
    ],
    targets: productionTargets + testTargets,
    swiftLanguageModes: [.v6]
)
