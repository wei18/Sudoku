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
let gameStateDep: Target.Dependency = .product(name: "SudokuGameState", package: "SudokuCoreKit")
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
// #287 Phase 2: RemindersKit reminder mechanism (protocol seams + value types).
// SudokuUI's `ReminderPrimerCoordinator` depends on the seams only; the live
// `UserNotifications` conformers + the UNUserNotificationCenterDelegate stay in
// SudokuAppComposition. `RemindersTesting` provides the fakes for the coordinator tests.
let remindersDep: Target.Dependency = .product(name: "Reminders", package: "RemindersKit")
let remindersTestingDep: Target.Dependency = .product(name: "RemindersTesting", package: "RemindersKit")
// refactor/settingskit-target (2026-06-09): the shared Settings screen + the
// reminders UI (primer sheet, `ReminderSettingsSection` / `ReminderSettingsModel`,
// `ReminderPermissionModel`) moved out of GameShellUI into the sibling SettingsKit
// package. `SettingsView` + `ReminderPrimerCoordinator` + `CompletionView` consume
// these from `SettingsUI`; SudokuAppComposition builds the entry configs.
let settingsUIDep: Target.Dependency = .product(name: "SettingsUI", package: "SettingsKit")
// #330 P2: shared game-audio mechanism. SudokuUI fires gameplay cues via the
// `SoundPlaying` seam (defaults to Noop); SudokuAppComposition builds the Live audio
// stack (`LiveAudioSession` + `LiveHaptics` + `LiveSoundPlayer`) +
// `AudioSettingsModel`. Test targets pull `GameAudioTesting`'s order-preserving
// fakes. No `AVFoundation` leaks past GameAudioKit's Live files.
let gameAudioDep: Target.Dependency = .product(name: "GameAudio", package: "GameAudioKit")
let gameAudioTestingDep: Target.Dependency = .product(name: "GameAudioTesting", package: "GameAudioKit")
// #448 step 1a: generic app-launch coordinator `GameRootViewModel<Route>` lives
// in GameAppKit (which is allowed Persistence/GameCenter/Telemetry deps, unlike
// the zero-dep GameShellUI). SudokuUI's `RootViewModel` is now a typealias over
// `GameRootViewModel<AppRoute>`.
let gameAppDep: Target.Dependency = .product(name: "GameAppKit", package: "GameAppKit")
// #750: shared ASC-screenshot render machinery (ASCProfile / emitASCScreenshot),
// extracted out of the byte-drifted per-app copies. Test-only — wired into the
// UITests target's dependency list, never a production target.
let gameTestSupportDep: Target.Dependency = .product(name: "GameTestSupportKit", package: "GameTestSupportKit")

// MARK: - Production targets

let productionTargets: [Target] = [
    .target(name: "SudokuPersistence", dependencies: [sudokuEngineDep, telemetryDep], swiftSettings: swiftSettings),
    .target(
        name: "SudokuUI",
        dependencies: [
            gameStateDep,
            "SudokuPersistence",
            persistenceDep,
            gameCenterClientDep,
            telemetryDep,
            // v2.3.3: RouteFactory holds AdProvider / IAPClient / AdGate
            // protocol deps so individual destination Views (v2.3.4-6) can
            // pull them at construction. SudokuUI does not depend on the
            // AdMob / StoreKit2 concrete-impl targets — those stay isolated
            // in SudokuAppComposition (foundations.md §9.1).
            .product(name: "MonetizationCore", package: "AppMonetizationKit"),
            // MS monetization wire Phase 1 (2026-06-02): shared rows
            // (`RemoveAdsRow` / `RestorePurchasesRow` / `AdsRemovedRow`)
            // + `MonetizationStateController` + `ToastController` /
            // `ToastView` live in MonetizationUI so Minesweeper can mount
            // the same surfaces in Phase 3. SudokuUI consumes these from
            // `SettingsView` + `RootView` + `RouteFactory` and resolves
            // its theme tints at the call site via `tintColor:` params.
            .product(name: "MonetizationUI", package: "AppMonetizationKit"),
            // PR X1: NavigationStackHost lives here now. Will grow as more
            // shell components extract (RootView, Settings shell, Daily /
            // Practice hubs — Phase X PRs).
            .product(name: "GameShellUI", package: "GameShellKit"),
            // #448 step 1a: `RootViewModel = GameRootViewModel<AppRoute>`.
            gameAppDep,
            // #287 Phase 2: ReminderPrimerCoordinator names the `ReminderScheduler`
            // / `NotificationAuthorizing` seams + `ReminderContent`. UI/logic only;
            // never `UserNotifications` (that stays in SudokuAppComposition's Live layer).
            remindersDep,
            // refactor/settingskit-target: the shared Settings screen + reminders UI
            // (primer sheet, settings/permission models) moved here. SettingsView,
            // ReminderPrimerCoordinator, and CompletionView consume them via `import SettingsUI`.
            settingsUIDep,
            // #330 P2: `GameViewModel` fires gameplay cues through the
            // `SoundPlaying` seam (defaults to `NoopSoundPlaying`). No
            // `AVFoundation` — that stays in GameAudioKit's Live files.
            gameAudioDep,
            // #178: invariant-reporting tool. `reportIssue(_:)` surfaces
            // impossible-state / programmer-error catches (fails tests +
            // purple-warns in #Preview, non-fatal in release). Deliberate
            // restricted-import allowance — treated like a logger, NOT a
            // replacement for ErrorReporter (which routes expected runtime
            // failures to telemetry). See foundations.md §3.
            .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
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
            "SudokuPersistence",
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
        name: "SudokuAppComposition",
        dependencies: [
            sudokuEngineDep,
            gameStateDep,
            "SudokuPersistence",
            persistenceDep,
            gameCenterClientDep,
            telemetryDep,
            "SudokuUI",
            // #510: direct GameAppKit dep so `rootView` can name the DEBUG-only
            // `UITestRouteModifier` (a transitive re-export via SudokuUI does not
            // satisfy Swift 6 module name resolution at the target boundary).
            gameAppDep,
            // PR X2: explicit GameShellUI dep so SudokuAppComposition can name
            // `any RouteFactory<AppRoute>` (the protocol moved out of
            // SudokuUI into GameShellUI). SudokuUI still re-exports the
            // type via `public import GameShellUI`, but a transitive
            // re-export does not satisfy Swift 6 module name resolution
            // — SudokuAppComposition needs the dep at its target boundary.
            .product(name: "GameShellUI", package: "GameShellKit"),
            // #287 Phase 2: `.live()` wires `LiveNotificationAuthorizer` +
            // `LiveReminderScheduler` and sets the `UNUserNotificationCenterDelegate`.
            // This is the only target allowed `import UserNotifications` (transitively
            // via the Reminders Live conformers — the delegate itself imports it here).
            remindersDep,
            // refactor/settingskit-target: SudokuAppComposition builds the
            // `ReminderSettingsEntry` (which wraps `ReminderSettingsModel` /
            // `ReminderPermissionModel`) + names `SettingsNoticesConfig`, all moved
            // to SettingsUI.
            settingsUIDep,
            // #330 P2: composition root builds the Live audio stack
            // (`LiveAudioSession` + `LiveHaptics` + `LiveSoundPlayer`) +
            // `AudioSettingsModel`, and injects the `SoundPlaying` into the
            // gameplay VM + the `AudioSettingsModel` into Settings. This is the
            // only Sudoku target that constructs the Live conformers (which
            // transitively reach AVFoundation inside GameAudioKit).
            gameAudioDep,
            // `.preview()` and `.tests()` factories pull from SudokuKitTesting
            // for the protocol fakes. Shipped in the binary; the `.live()`
            // factory does not reference them so dead-code elimination keeps
            // the cost bounded.
            "SudokuKitTesting",
            // Stage 3: GameCenter fakes carved out of SudokuKitTesting into
            // GameCenterTesting; `Preview.swift` consumes `FakeGameCenterClient`
            // for the `.preview()` factory.
            gameCenterTestingDep,
            // Monetization surfaces referenced by the composition types
            // (MonetizationCore/MonetizationUI); since #556/#557 the live
            // UMP → ATT → AdMob boot construction lives in GameAppKit's
            // makeGameApp, not here. Preview uses MonetizationTesting fakes.
            .product(name: "MonetizationCore", package: "AppMonetizationKit"),
            .product(name: "MonetizationUI", package: "AppMonetizationKit"),
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
    // SudokuUITests + SudokuAppCompositionTests are carved out below because they
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
    // MS monetization wire Phase 1 (2026-06-02): tests reference
    // `MonetizationStateController`, `ToastController`, `Toast`,
    // `removeAdsProductId` (moved here from SudokuUI).
    .product(name: "MonetizationUI", package: "AppMonetizationKit"),
    .product(name: "MonetizationTesting", package: "AppMonetizationKit"),
]

let testTargets: [Target] = [
    testTarget("SudokuPersistence", dependencies: ["SudokuPersistence", telemetryTestingDep]),
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
            gameAppDep,
            persistenceDep,
            gameCenterClientDep,
            gameCenterTestingDep,
            // #278 Tier-1 Phase 1: ThemeTests names the bare `Theme` protocol,
            // which moved to GameShellUI. A transitive re-export through
            // SudokuUI does not satisfy Swift 6 module name resolution for a
            // direct `import GameShellUI` — same reason SudokuAppComposition needs
            // the explicit dep at its boundary.
            .product(name: "GameShellUI", package: "GameShellKit"),
            // #287 Phase 2: ReminderPrimerCoordinatorTests drive the coordinator
            // with FakeReminderScheduler / FakeNotificationAuthorizing.
            remindersDep,
            remindersTestingDep,
            // refactor/settingskit-target: SettingsViewTests +
            // ReminderPrimerCoordinatorTests name `SettingsScreen` / the reminder
            // copy + model types, now in SettingsUI.
            settingsUIDep,
            // #330 P2: GameViewModelAudioTests drive the VM with the
            // order-preserving `FakeSoundPlaying` to assert the cue fired at
            // each gameplay trigger point.
            gameAudioDep,
            gameAudioTestingDep,
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            // #750: ASCScreenshotEmitTests draws ASCProfile / emitASCScreenshot
            // from the shared package instead of a forked local copy.
            gameTestSupportDep,
        ] + monetizationTestDeps,
        resources: [.copy("__Snapshots__")],
        swiftSettings: swiftSettings
    ),
    // SudokuAppCompositionTests pulls in AdsAdMob so v2.3.7 BootOrderTests can drive
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
        name: "SudokuAppCompositionTests",
        dependencies: [
            "SudokuAppComposition",
            // #639: RouteFactoryTests moved here with LiveRouteFactory; it
            // `@testable import`s SudokuUI (AppRoute + destination views) and
            // names SudokuPersistence types when building the factory's deps.
            "SudokuUI",
            "SudokuPersistence",
            persistenceDep,
            gameCenterClientDep,
            gameCenterTestingDep,
            .product(name: "AdsAdMob", package: "AppMonetizationKit"),
            "SudokuKitTesting",
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            // #909: ReminderSettingsIdentityTests builds a real entry over the
            // Reminders Noop conformers to prove same-instance across renders.
            remindersDep,
            settingsUIDep,
        ] + monetizationTestDeps,
        resources: [
            // Renamed to `.json` extension so xcodebuild's `.xcstrings`
            // compiler doesn't process it into per-locale `.strings` files
            // and strip the source. The content is plain JSON; the tests
            // read it as the literal catalog source.
            .copy("Resources/Localizable.xcstrings.json"),
            .copy("Resources/PrivacyInfo.xcprivacy"),
            // App target's Info.plist, renamed to AppInfo.plist because
            // SPM bans `Info.plist` as a top-level bundle resource. Read
            // raw via PropertyListSerialization in the AdMob-key smoke
            // test so XCC (where the source tree isn't on the test
            // runner) can still verify the keys. Kept in sync manually
            // with Sudoku/Info.plist — same precedent as PrivacyInfo.xcprivacy.
            .copy("Resources/AppInfo.plist"),
        ],
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
        .library(name: "SudokuPersistence", targets: ["SudokuPersistence"]),
        .library(name: "SudokuUI", targets: ["SudokuUI"]),
        .library(name: "SudokuKitTesting", targets: ["SudokuKitTesting"]),
        .library(name: "SudokuAppComposition", targets: ["SudokuAppComposition"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
        // #178: swift-issue-reporting (`IssueReporting`). Already resolved as a
        // transitive dep of swift-snapshot-testing (1.9.0); promoted to a
        // direct dep so production UI targets can `import IssueReporting` for
        // invariant reporting. `from: "1.9.0"` matches the resolved revision —
        // no Package.resolved churn beyond the new direct-dep entry.
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.9.0"),
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
        .package(name: "GameShellKit", path: "../GameShellKit"),
        // #448 step 1a: app-level shell sitting above GameShellUI, hosting the
        // generic `GameRootViewModel<Route>`. Unlike the zero-dep GameShellKit,
        // GameAppKit is allowed Persistence / GameCenter / Telemetry deps.
        .package(name: "GameAppKit", path: "../GameAppKit"),
        // #287 Phase 2: shared local-notification reminder mechanism. Leaf
        // sibling package (protocol seams + value types + Live UN conformers).
        // SudokuUI consumes the `Reminders` seams; SudokuAppComposition wires the Live
        // conformers + the notification-center delegate.
        .package(name: "RemindersKit", path: "../RemindersKit"),
        // refactor/settingskit-target (2026-06-09): shared Settings screen + the
        // reminders UI carved out of GameShellUI into this sibling package.
        // SudokuUI / SudokuAppComposition consume the `SettingsUI` product.
        .package(name: "SettingsKit", path: "../SettingsKit"),
        // #330 P2: shared game-audio mechanism (protocol seams + value types +
        // Noop/Live conformers + GameAudioTesting fakes). Leaf sibling package;
        // SettingsKit already depends on it for `AudioSettingsModel`.
        .package(name: "GameAudioKit", path: "../GameAudioKit"),
        // #750: shared ASC-screenshot render machinery (test-only), consumed by
        // SudokuUITests. See `docs/foundations.md` for the extraction rationale.
        .package(name: "GameTestSupportKit", path: "../GameTestSupportKit"),
    ],
    targets: productionTargets + testTargets,
    swiftLanguageModes: [.v6]
)
