// swift-tools-version: 6.2

import PackageDescription

// MARK: - Shared settings (foundations.md §1: Swift 6 + complete concurrency)

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

// MARK: - Shared dep shorthands
//
// SudokuEngine + GameState live in the sibling SudokuCoreKit package as of
// the 2026-05-26 module split (see `docs/foundations.md §2`). Every target
// that previously listed them as in-package string deps now pulls them via
// `.product(name:package:)` from SudokuCoreKit.

let sudokuEngineDep: Target.Dependency = .product(name: "SudokuEngine", package: "SudokuCoreKit")
let gameStateDep: Target.Dependency = .product(name: "GameState", package: "SudokuCoreKit")
// Telemetry extracted into sibling TelemetryKit package on 2026-05-26
// (Stage 2 of the module split). See `docs/foundations.md §2`.
let telemetryDep: Target.Dependency = .product(name: "Telemetry", package: "TelemetryKit")
// TelemetryTesting — FakeLogger / RecordingSink / MetricPayloadFixtures.
// Carved out of SudokuKitTesting/Telemetry/ on Stage 2 so test targets that
// only need the Telemetry-shaped fixtures don't pay for the broader
// SudokuKitTesting surface.
let telemetryTestingDep: Target.Dependency = .product(name: "TelemetryTesting", package: "TelemetryKit")
// Persistence + GameCenterClient extracted into sibling PersistenceKit /
// GameCenterKit packages on 2026-05-26 (Stage 3 of the module split). See
// `docs/foundations.md §2`. Their fixtures live in PersistenceTesting /
// GameCenterTesting library products on the same sibling packages.
let persistenceDep: Target.Dependency = .product(name: "Persistence", package: "PersistenceKit")
let gameCenterClientDep: Target.Dependency = .product(name: "GameCenterClient", package: "GameCenterKit")
let gameCenterTestingDep: Target.Dependency = .product(name: "GameCenterTesting", package: "GameCenterKit")

// MARK: - Production targets

let productionTargets: [Target] = [
    .target(name: "PuzzleStore", dependencies: [sudokuEngineDep, telemetryDep], swiftSettings: swiftSettings),
    .target(
        name: "SudokuUI",
        dependencies: [
            gameStateDep,
            "PuzzleStore",
            persistenceDep,
            gameCenterClientDep,
            telemetryDep,
            // v2.3.3: RouteFactory holds AdProvider / IAPClient / AdGate
            // protocol deps so individual destination Views (v2.3.4-6) can
            // pull them at construction. SudokuUI does not depend on the
            // AdMob / StoreKit2 concrete-impl targets — those stay isolated
            // in AppComposition (foundations.md §9.1).
            .product(name: "MonetizationCore", package: "AppMonetizationKit"),
            // PR X1: NavigationStackHost lives here now. Will grow as more
            // shell components extract (RootView, Settings shell, Daily /
            // Practice hubs — Phase X PRs).
            .product(name: "GameShellUI", package: "GameShellKit"),
        ],
        swiftSettings: swiftSettings
    ),
    .target(
        name: "SudokuKitTesting",
        // `PersistenceTesting` pulled in for `PuzzleFixtures` (consumed by
        // `FakePuzzleProvider` in this target). PuzzleFixtures lives in
        // PersistenceTesting after Stage 3 carve-out because PersistenceTests
        // are its primary consumer; SudokuKitTesting reaches for it via the
        // existing SudokuKit → PersistenceKit dep arrow (no cycle).
        dependencies: [
            sudokuEngineDep,
            gameStateDep,
            "PuzzleStore",
            persistenceDep,
            .product(name: "PersistenceTesting", package: "PersistenceKit"),
            gameCenterClientDep,
            telemetryDep,
        ],
        swiftSettings: swiftSettings
    ),
    // Phase 9.1: production composition root. The App target is intentionally
    // thin and depends only on this product (which re-exports SudokuUI via
    // its public surface). Keeps the DI plumbing inside the SwiftPM package
    // where it's testable.
    .target(
        name: "AppComposition",
        dependencies: [
            sudokuEngineDep,
            gameStateDep,
            "PuzzleStore",
            persistenceDep,
            gameCenterClientDep,
            telemetryDep,
            "SudokuUI",
            // PR X2: explicit GameShellUI dep so AppComposition can name
            // `any RouteFactory<AppRoute>` (the protocol moved out of
            // SudokuUI into GameShellUI). SudokuUI still re-exports the
            // type via `public import GameShellUI`, but a transitive
            // re-export does not satisfy Swift 6 module name resolution
            // — AppComposition needs the dep at its target boundary.
            .product(name: "GameShellUI", package: "GameShellKit"),
            // `.preview()` and `.tests()` factories pull from SudokuKitTesting
            // for the protocol fakes. Shipped in the binary; the `.live()`
            // factory does not reference them so dead-code elimination keeps
            // the cost bounded.
            "SudokuKitTesting",
            // Stage 3: GameCenter fakes carved out of SudokuKitTesting into
            // GameCenterTesting; `Preview.swift` consumes `FakeGameCenterClient`
            // for the `.preview()` factory.
            gameCenterTestingDep,
            // v2.3.2: monetization wiring. AppComposition.live builds
            // LiveAdMobAdProvider + LiveStoreKit2IAPClient + AdGate via
            // LiveMonetizationStateStore. Preview / tests use MonetizationTesting fakes.
            .product(name: "MonetizationCore", package: "AppMonetizationKit"),
            .product(name: "AdsAdMob", package: "AppMonetizationKit"),
            .product(name: "IAPStoreKit2", package: "AppMonetizationKit"),
            .product(name: "MonetizationTesting", package: "AppMonetizationKit"),
        ],
        swiftSettings: swiftSettings
    ),
]

// MARK: - Test targets (one per production target, except SudokuKitTesting which
// IS the shared testing helpers consumed by these test targets.)

func testTarget(_ name: String, dependencies: [Target.Dependency]) -> Target {
    // Generic helper for test targets without a `resources:` block.
    // SudokuUITests + AppCompositionTests are carved out below because they
    // need explicit `resources:` declarations (issue #188 — bundle snapshot
    // baselines via Bundle.module so XCC's distributed test runner can find
    // them at runtime).
    .testTarget(
        name: "\(name)Tests",
        dependencies: dependencies + [
            "SudokuKitTesting",
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
        ],
        swiftSettings: swiftSettings
    )
}

// Convenience dep set used by tests that need to construct AdGate / monetization fakes.
let monetizationTestDeps: [Target.Dependency] = [
    .product(name: "MonetizationCore", package: "AppMonetizationKit"),
    .product(name: "MonetizationTesting", package: "AppMonetizationKit"),
]

let testTargets: [Target] = [
    testTarget("PuzzleStore", dependencies: ["PuzzleStore", telemetryTestingDep]),
    // SudokuUITests carved out of the `testTarget()` helper because it needs
    // `__Snapshots__/` declared as a bundle resource. PR #185 wired the
    // Sudoku scheme's testAction via .xctestplan, surfacing that
    // pointfreeco/swift-snapshot-testing's default `#filePath`-walk fails on
    // Xcode Cloud: the test runner is on a different machine than the build
    // + source tree, so the PNG baselines under __Snapshots__/ aren't
    // reachable. `.copy("__Snapshots__")` bundles them into the .xctest so
    // `Bundle.module.resourceURL` resolves at runtime, anywhere (see
    // SnapshotConfig.swift `SnapshotPaths` helper). Closes #188.
    .testTarget(
        name: "SudokuUITests",
        dependencies: [
            "SudokuUI",
            "SudokuKitTesting",
            persistenceDep,
            gameCenterClientDep,
            gameCenterTestingDep,
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
        ] + monetizationTestDeps,
        resources: [.copy("__Snapshots__")],
        swiftSettings: swiftSettings
    ),
    // AppCompositionTests pulls in AdsAdMob so v2.3.7 BootOrderTests can drive
    // `MonetizationBootCoordinator` directly with recording bridges.
    //
    // Direct .testTarget (vs the `testTarget()` helper above) because we need
    // a `resources:` block. PR #185 wired the Sudoku scheme's testAction via
    // .xctestplan, surfacing that L10nTests + PrivacyManifestTests used
    // `#filePath`-walk to read Sudoku/Resources/* — that works locally but on
    // Xcode Cloud the test runner is on a different machine than the build
    // and source tree, so the files aren't there at runtime. Bundling the
    // two source files as test resources (literal copies under Resources/,
    // with `.xcstrings` renamed to `.json` so the xcstrings compiler skips
    // them — see the `resources:` block below) lets
    // Bundle.module.url(forResource:) find them at runtime, anywhere.
    .testTarget(
        name: "AppCompositionTests",
        dependencies: [
            "AppComposition",
            persistenceDep,
            gameCenterClientDep,
            gameCenterTestingDep,
            .product(name: "AdsAdMob", package: "AppMonetizationKit"),
            "SudokuKitTesting",
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
        ] + monetizationTestDeps,
        resources: [
            // Renamed to `.json` extension so xcodebuild's `.xcstrings`
            // compiler doesn't process it into per-locale `.strings` files
            // and strip the source. The content is plain JSON; the tests
            // read it as the literal catalog source.
            .copy("Resources/Localizable.xcstrings.json"),
            .copy("Resources/PrivacyInfo.xcprivacy"),
        ],
        swiftSettings: swiftSettings
    ),
]

// MARK: - ASCRegister CLI (additive tool target; not part of the App binary)
//
// Bootstraps Game Center achievements + leaderboards in App Store Connect
// via the ASC API. Pure Foundation + CryptoKit — no external deps. Lives in
// the SudokuKit package so it can share consistency tests with the
// production GameCenterClient IDs.

let ascRegisterTargets: [Target] = [
    .executableTarget(
        name: "ASCRegister",
        dependencies: [],
        path: "Sources/ASCRegister",
        resources: [.copy("Strings/gc-strings.xcstrings.patch")],
        swiftSettings: swiftSettings
    ),
    .testTarget(
        name: "ASCRegisterTests",
        dependencies: ["ASCRegister"],
        path: "Tests/ASCRegisterTests",
        swiftSettings: swiftSettings
    ),
]

// MARK: - Package

let package = Package(
    name: "SudokuKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "PuzzleStore", targets: ["PuzzleStore"]),
        .library(name: "SudokuUI", targets: ["SudokuUI"]),
        .library(name: "SudokuKitTesting", targets: ["SudokuKitTesting"]),
        .library(name: "AppComposition", targets: ["AppComposition"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
        // 2026-05-26 module split: SudokuEngine + GameState extracted into
        // sibling local package so a future Telemetry-only extraction is
        // unblocked. See `docs/foundations.md §2`.
        .package(name: "SudokuCoreKit", path: "../SudokuCoreKit"),
        // 2026-05-26 Stage 2 module split: Telemetry extracted into sibling
        // TelemetryKit package so it can be reused across apps. Telemetry is
        // pure value types + protocol seams, zero Apple framework imports —
        // suitable as a leaf package. See `docs/foundations.md §2`.
        .package(name: "TelemetryKit", path: "../TelemetryKit"),
        // 2026-05-26 Stage 3 module split: Persistence + GameCenterClient
        // extracted into sibling local packages. PersistenceKit hosts the
        // CloudKit Private-DB stack; GameCenterKit hosts the GameKit seam.
        // See `docs/foundations.md §2`.
        .package(name: "PersistenceKit", path: "../PersistenceKit"),
        .package(name: "GameCenterKit", path: "../GameCenterKit"),
        // v2.3.2: sibling local package providing MonetizationCore +
        // AdsAdMob (Google Mobile Ads bridge) + IAPStoreKit2 (StoreKit2 bridge)
        // + MonetizationTesting fakes. Lives one directory up under Packages/.
        .package(name: "AppMonetizationKit", path: "../AppMonetizationKit"),
        // PR X1 (2026-06-01): game-agnostic UI shell extracted into
        // GameShellKit so MinesweeperKit + a future third game's Kit can
        // host the same navigation / settings / hub shapes. SudokuKit only
        // ships gameplay UI + Sudoku-specific composition.
        // See `meetings/2026-06-01_minesweeper-dev-roadmap.md` Phase X.
        .package(name: "GameShellKit", path: "../GameShellKit"),
    ],
    targets: productionTargets + testTargets + ascRegisterTargets,
    swiftLanguageModes: [.v6]
)
