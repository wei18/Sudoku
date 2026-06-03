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
// MinesweeperKit is the UI + composition shell for the Minesweeper app target,
// siblings to SudokuKit. PR D scope is skeleton-only — both modules ship as
// placeholders so `Project.swift`'s Minesweeper target links a real product
// and `tuist generate` produces both schemes. Real navigation, BoardView, and
// AppComposition wiring land in follow-up PRs.
//
// Module names `MinesweeperUI` and `MinesweeperAppComposition` avoid the
// `SudokuUI` / `AppComposition` collision that would otherwise occur when
// both packages join the same Xcode project's package graph.

let productionTargets: [Target] = [
    .target(
        name: "MinesweeperUI",
        dependencies: [
            .product(name: "MinesweeperEngine", package: "MinesweeperCoreKit"),
            .product(name: "MinesweeperGameState", package: "MinesweeperCoreKit"),
            // Standard nav wire (2026-06-02): MinesweeperRoot wraps
            // `RootShellView`, SettingsView wraps `SettingsShellView`. Both
            // come from GameShellKit.
            .product(name: "GameShellUI", package: "GameShellKit"),
            // MS monetization wire Phase 3 (2026-06-03): SettingsView mounts
            // the shared `RemoveAdsRow` / `AdsRemovedRow` / `RestorePurchasesRow`.
            .product(name: "MonetizationUI", package: "AppMonetizationKit"),
        ],
        swiftSettings: swiftSettings
    ),
    .target(
        name: "MinesweeperAppComposition",
        dependencies: [
            "MinesweeperUI",
            // LiveRouteFactory conforms to `RouteFactory<AppRoute>` from
            // GameShellUI.
            .product(name: "GameShellUI", package: "GameShellKit"),
            // Telemetry + ErrorReporter seam (2026-06-02 parity audit). Mirror
            // Sudoku's AppComposition shape — `.live()` constructs OSLog-backed
            // Telemetry + LiveErrorReporter; `.preview()` wires empty-sinks +
            // NoopErrorReporter. View-level usage is intentionally deferred.
            .product(name: "Telemetry", package: "TelemetryKit"),
            // MS monetization wire Phase 3 (2026-06-03). NOTE: no AdsAdMob —
            // U15 deferred; `.live()` uses `NoopAdProvider` from MonetizationCore.
            .product(name: "Persistence", package: "PersistenceKit"),
            .product(name: "MonetizationCore", package: "AppMonetizationKit"),
            .product(name: "MonetizationUI", package: "AppMonetizationKit"),
            .product(name: "IAPStoreKit2", package: "AppMonetizationKit"),
            // `.preview()` wires `FakeIAPClient` / `FakeAdGateStateStore` /
            // `FakeAdProvider` so SwiftUI Previews stay zero-IO. Production
            // bag uses Live variants only — but the tier-1 helpers from
            // MonetizationTesting are reused for both `.preview()` and the
            // `MinesweeperAppCompositionTests` shape-coverage suite, matching
            // Sudoku's pattern (Preview.swift + AppCompositionTests). The
            // type leaks into the production target but never instantiates
            // outside `.preview()` — same precedent set by SudokuKit Preview.
            .product(name: "MonetizationTesting", package: "AppMonetizationKit"),
        ],
        swiftSettings: swiftSettings
    ),
]

let testTargets: [Target] = [
    .testTarget(
        name: "MinesweeperUITests",
        dependencies: [
            "MinesweeperUI",
            // Standard nav wire tests (2026-06-02 Track c.1) cover
            // `LiveRouteFactory`'s route → view mapping. Co-located in the
            // existing test target rather than spinning up a new one — the
            // factory is a thin RouteFactory conformance, not enough surface
            // to justify separate scoping.
            "MinesweeperAppComposition",
            // 2026-06-02 telemetry-wire tests construct `.preview()` +
            // `.live()` factories and exercise `observe(_:)` / `report(_:)`
            // smoke calls — direct `import Telemetry` needed.
            .product(name: "Telemetry", package: "TelemetryKit"),
        ],
        swiftSettings: swiftSettings
    ),
]

// MARK: - Package

let package = Package(
    name: "MinesweeperKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "MinesweeperUI", targets: ["MinesweeperUI"]),
        .library(name: "MinesweeperAppComposition", targets: ["MinesweeperAppComposition"]),
    ],
    dependencies: [
        .package(path: "../MinesweeperCoreKit"),
        .package(name: "GameShellKit", path: "../GameShellKit"),
        .package(name: "TelemetryKit", path: "../TelemetryKit"),
        .package(name: "PersistenceKit", path: "../PersistenceKit"),
        .package(name: "AppMonetizationKit", path: "../AppMonetizationKit"),
    ],
    targets: productionTargets + testTargets,
    swiftLanguageModes: [.v6]
)
