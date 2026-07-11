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
// sibling to SudokuKit. Fully implemented (shipped, v2.6): MinesweeperUI hosts
// navigation + BoardView + Daily/Practice; MinesweeperAppComposition wires the
// live persistence / Game Center / monetization / audio stack.
//
// Module names `MinesweeperUI` and `MinesweeperAppComposition` avoid the
// `SudokuUI` / `SudokuAppComposition` collision that would otherwise occur when
// both packages join the same Xcode project's package graph.

let productionTargets: [Target] = [
    // #455: MS saved-game store — maps the Codable `MinesweeperSessionSnapshot`
    // ↔ CloudKit `RecordPayload` via the shared public `PrivateCKGateway`,
    // returning the MS-native `MinesweeperSavedGameSummary` (the shared
    // `SavedGameSummary` is Sudoku-typed; see #455 thread). INERT until the
    // user-owned ck:schema deploy adds `SavedGame` to the MS container —
    // composition wiring is #455 step 4.
    .target(
        name: "MinesweeperPersistence",
        dependencies: [
            .product(name: "MinesweeperEngine", package: "MinesweeperCoreKit"),
            .product(name: "MinesweeperGameState", package: "MinesweeperCoreKit"),
            .product(name: "Persistence", package: "PersistenceKit"),
            // #455 step 4: save funnel mirrors Sudoku's SavedGameStore
            // (.gameSaved / .gameSaveFailed).
            .product(name: "Telemetry", package: "TelemetryKit"),
        ],
        swiftSettings: swiftSettings
    ),
    .target(
        name: "MinesweeperUI",
        dependencies: [
            .product(name: "MinesweeperEngine", package: "MinesweeperCoreKit"),
            .product(name: "MinesweeperGameState", package: "MinesweeperCoreKit"),
            // Standard nav wire (2026-06-02): MinesweeperRoot wraps
            // `RootShellView` (still in GameShellUI).
            .product(name: "GameShellUI", package: "GameShellKit"),
            // refactor/settingskit-target (2026-06-09): SettingsView wraps
            // `SettingsScreen` / `SettingsShellView` + builds the reminders entry
            // (`ReminderSettingsModel` etc.) — all moved into SettingsUI.
            .product(name: "SettingsUI", package: "SettingsKit"),
            // MS monetization wire Phase 3 (2026-06-03): SettingsView mounts
            // the shared `RemoveAdsRow` / `AdsRemovedRow` / `RestorePurchasesRow`.
            .product(name: "MonetizationUI", package: "AppMonetizationKit"),
            // U15 (2026-06-03): MinesweeperBannerSlotView + MinesweeperBoardView
            // touch `AdProvider` / `AdGate` directly.
            .product(name: "MonetizationCore", package: "AppMonetizationKit"),
            // #290: MinesweeperDailyHubViewModel reads completed daily ids via
            // `PersistenceProtocol.fetchCompletedDailyIds` and funnels a
            // completion-fetch failure through `Telemetry`'s `ErrorReporter`
            // (graceful-degrade) — mirrors SudokuUI.DailyHubViewModel's deps.
            .product(name: "Persistence", package: "PersistenceKit"),
            .product(name: "Telemetry", package: "TelemetryKit"),
            // #291: Game Center seam. `MinesweeperGameViewModel` submits a
            // best-time on win via the game-agnostic `GameCenterClient`
            // protocol; the shared `GameCenterDashboard` (#560) presents the
            // native GC modal. GameKit stays fully encapsulated inside
            // GameCenterKit — MinesweeperUI sees only the GameKit-free surface.
            .product(name: "GameCenterClient", package: "GameCenterKit"),
            // #178: invariant-reporting tool — mirrors SudokuUI. `reportIssue(_:)`
            // surfaces impossible-state catches (fails tests, purple-warns in
            // #Preview, non-fatal in release). Deliberate restricted-import
            // allowance, not a replacement for ErrorReporter. See foundations.md §3.
            .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
            // #330 P2: `MinesweeperGameViewModel` fires `AudioEvent`s through the
            // injected `SoundPlaying` seam; the MS event constants live in this
            // target. `AVFoundation` stays inside GameAudioKit's Live target — the
            // VM sees only the protocol + value types.
            .product(name: "GameAudio", package: "GameAudioKit"),
            // #448 step 1b: `MinesweeperRootViewModel` is now a typealias over the
            // shared `GameAppKit.GameRootViewModel<AppRoute>` (was a byte-identical
            // bespoke class). GameAppKit is allowed Persistence/GameCenter/Telemetry
            // deps, unlike the zero-dep GameShellUI. Mirrors SudokuUI's wire (1a).
            .product(name: "GameAppKit", package: "GameAppKit"),
            // #455 step 4: `MinesweeperGameViewModel` persists in-progress boards
            // through `MinesweeperSavedGameStore`; `MinesweeperBoardLoaderView`
            // restores them for the `.resumeBoard` route. Same-package target.
            "MinesweeperPersistence",
        ],
        swiftSettings: swiftSettings
    ),
    .target(
        name: "MinesweeperAppComposition",
        dependencies: [
            "MinesweeperUI",
            // #455 step 4: `.live()` builds the MinesweeperSavedGameStore over
            // the public gateway factory; the route factory threads it into
            // boards + the `.resumeBoard` loader.
            "MinesweeperPersistence",
            // #455 step 4: `.live()`'s fetchResume closure names
            // `ResumeCandidate<AppRoute>` (the #460 game-agnostic resume DTO).
            .product(name: "GameAppKit", package: "GameAppKit"),
            // LiveRouteFactory conforms to `RouteFactory<AppRoute>` from
            // GameShellUI.
            .product(name: "GameShellUI", package: "GameShellKit"),
            // Telemetry + ErrorReporter seam (2026-06-02 parity audit). Mirror
            // Sudoku's SudokuAppComposition shape — `.live()` constructs OSLog-backed
            // Telemetry + LiveErrorReporter; `.preview()` wires empty-sinks +
            // NoopErrorReporter. View-level usage is intentionally deferred.
            .product(name: "Telemetry", package: "TelemetryKit"),
            // MS monetization wire Phase 3 + U15 (2026-06-03). AdsAdMob wires
            // `LiveAdMobAdProvider` on iOS; on macOS `.live()` falls back to
            // `NoopAdProvider` from MonetizationCore (the AdMob SDK ships an
            // iOS-only xcframework).
            .product(name: "Persistence", package: "PersistenceKit"),
            // #261: `.preview()` wires `FakePersistence` (zero-IO) instead of
            // `LivePersistence` so any future Preview path that calls
            // bootstrap()/latestInProgress() stays trap-free. Production target
            // intentionally deps the Testing product — same pattern as Sudoku's
            // SudokuAppComposition (its FakePersistence ships via SudokuKitTesting).
            .product(name: "PersistenceTesting", package: "PersistenceKit"),
            .product(name: "MonetizationCore", package: "AppMonetizationKit"),
            .product(name: "MonetizationUI", package: "AppMonetizationKit"),
            .product(name: "IAPStoreKit2", package: "AppMonetizationKit"),
            .product(name: "AdsAdMob", package: "AppMonetizationKit"),
            // `.preview()` wires `FakeIAPClient` / `FakeAdGateStateStore` /
            // `FakeAdProvider` so SwiftUI Previews stay zero-IO. Production
            // bag uses Live variants only — but the tier-1 helpers from
            // MonetizationTesting are reused for both `.preview()` and the
            // `MinesweeperAppCompositionTests` shape-coverage suite, matching
            // Sudoku's pattern (Preview.swift + AppCompositionTests). The
            // type leaks into the production target but never instantiates
            // outside `.preview()` — same precedent set by SudokuKit Preview.
            .product(name: "MonetizationTesting", package: "AppMonetizationKit"),
            // #291: `.live()` wires `LiveGameCenterClient(authDriver:
            // GKAuthDriver())`; `.preview()` wires `FakeGameCenterClient`.
            // Mirrors Sudoku's SudokuAppComposition (Live.swift / Preview.swift).
            .product(name: "GameCenterClient", package: "GameCenterKit"),
            .product(name: "GameCenterTesting", package: "GameCenterKit"),
            // #287: the shared local-notification reminder seam. `.live()` wires
            // `LiveReminderScheduler` / `LiveNotificationAuthorizer` (the only
            // files allowed to import `UserNotifications`) to drive the Settings
            // Reminders entry; the UI model/section come through GameShellUI.
            // Mirrors Sudoku's SudokuAppComposition RemindersKit wire.
            .product(name: "Reminders", package: "RemindersKit"),
            // refactor/settingskit-target (2026-06-09): Live.swift builds the
            // `MinesweeperReminderSettingsEntry` (wrapping `ReminderSettingsModel` /
            // `ReminderPermissionModel`) + names `SettingsNoticesConfig`;
            // LiveRouteFactory names `SettingsNoticesConfig` — all in SettingsUI.
            .product(name: "SettingsUI", package: "SettingsKit"),
            // #330 P2: `.live()` builds the Live audio stack (`LiveAudioSession` +
            // `LiveHaptics` + `LiveSoundPlayer`) and `AudioSettingsModel`; the VM /
            // route factory receive `SoundPlaying`. `.preview()` wires
            // `NoopSoundPlaying`. `AVFoundation` stays inside GameAudioKit's Live
            // files — composition sees only the public seams.
            .product(name: "GameAudio", package: "GameAudioKit"),
            // #720 G2: `Difficulty` named explicitly (as a type, not just an
            // inferred pattern-match binding) to seed/persist the Practice
            // hub's last-selected difficulty.
            .product(name: "MinesweeperEngine", package: "MinesweeperCoreKit"),
        ],
        swiftSettings: swiftSettings
    ),
]

let testTargets: [Target] = [
    // #455: store tests run against the shared `FakePrivateCKGateway` —
    // zero live CloudKit. (PersistenceTesting transitively drags SudokuCoreKit
    // into this test graph; harmless, same as MinesweeperUITests.)
    .testTarget(
        name: "MinesweeperPersistenceTests",
        dependencies: [
            "MinesweeperPersistence",
            .product(name: "PersistenceTesting", package: "PersistenceKit"),
        ],
        swiftSettings: swiftSettings
    ),
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
            // #291: submit-on-win + leaderboard-card present tests inject the
            // shared `FakeGameCenterClient` to assert call shape.
            .product(name: "GameCenterClient", package: "GameCenterKit"),
            .product(name: "GameCenterTesting", package: "GameCenterKit"),
            // #448: MinesweeperRootViewModelTests inject `FakePersistence`
            // (zero-IO) for the launch-bootstrap `persistence.bootstrap()` call.
            .product(name: "PersistenceTesting", package: "PersistenceKit"),
            // #530: offline-hub fake actors implement PersistenceProtocol, whose
            // method signatures use `Mode` / `GameSessionSnapshot` from SudokuCoreKit.
            .product(name: "SudokuGameState", package: "SudokuCoreKit"),
            .product(name: "SudokuEngine", package: "SudokuCoreKit"),
            // #455 step 4: persist-hook tests drive the VM's saved-game seam
            // against the fake gateway.
            "MinesweeperPersistence",
            // #278 Tier-1 Phase 2b: MS snapshot harness. Mirrors SudokuKit's
            // SudokuUITests snapshot dep — themed board baselines are the
            // Designer's visual-verification surface.
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            // #287: the SettingsView reminder-entry sentinel builds a
            // `ReminderSettingsModel` over the `Reminders` Noop conformers.
            .product(name: "Reminders", package: "RemindersKit"),
            // refactor/settingskit-target: MinesweeperSettingsViewTests name
            // `ReminderSettingsModel` / `SettingsScreen`, now in SettingsUI.
            .product(name: "SettingsUI", package: "SettingsKit"),
            // #330 P2: gameplay-audio tests inject `FakeSoundPlaying` to assert
            // which `AudioEvent` (+ haptic) each MS action fires.
            .product(name: "GameAudio", package: "GameAudioKit"),
            .product(name: "GameAudioTesting", package: "GameAudioKit"),
            // #750: ASCScreenshotEmitTests draws ASCProfile / emitASCScreenshot
            // from the shared package instead of a forked local copy.
            .product(name: "GameTestSupportKit", package: "GameTestSupportKit"),
        ],
        resources: [
            // App target's Info.plist, renamed to AppInfo.plist because
            // SPM bans `Info.plist` as a top-level bundle resource. Read
            // raw via PropertyListSerialization in the AdMob-key smoke
            // test so XCC (where the source tree isn't on the test
            // runner) can still verify the keys. Kept in sync manually
            // with Minesweeper/Info.plist — same precedent as Sudoku's
            // AppCompositionTests/Resources/PrivacyInfo.xcprivacy.
            .copy("Resources/AppInfo.plist"),
            // #278 Tier-1 Phase 2b: bundle the snapshot baselines so Xcode
            // Cloud's distributed test runner resolves them via Bundle.module
            // (same fix as SudokuUITests — see SnapshotConfig `SnapshotPaths`).
            .copy("__Snapshots__"),
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
        // #455: consumed by MinesweeperAppComposition in step 4 (fetchResume wire).
        .library(name: "MinesweeperPersistence", targets: ["MinesweeperPersistence"]),
    ],
    dependencies: [
        .package(path: "../MinesweeperCoreKit"),
        .package(name: "GameShellKit", path: "../GameShellKit"),
        .package(name: "TelemetryKit", path: "../TelemetryKit"),
        .package(name: "PersistenceKit", path: "../PersistenceKit"),
        .package(name: "AppMonetizationKit", path: "../AppMonetizationKit"),
        // #291: shared Game Center seam (GameCenterClient protocol + Live impl
        // in GameCenterKit; FakeGameCenterClient in GameCenterTesting).
        .package(name: "GameCenterKit", path: "../GameCenterKit"),
        // #287: shared local-notification reminder seam (sibling leaf package,
        // merged #318). `MinesweeperAppComposition` consumes the `Reminders`
        // product to wire the Live scheduler/authorizer for the Settings entry.
        .package(name: "RemindersKit", path: "../RemindersKit"),
        // refactor/settingskit-target (2026-06-09): shared Settings screen + the
        // reminders UI carved out of GameShellUI. `MinesweeperUI` /
        // `MinesweeperAppComposition` consume the `SettingsUI` product.
        .package(name: "SettingsKit", path: "../SettingsKit"),
        // #330 P2: shared game-audio seam (GameAudio protocols + value types +
        // Live impls; GameAudioTesting fakes). Mirrors SettingsKit's dep on it.
        .package(name: "GameAudioKit", path: "../GameAudioKit"),
        // #448 step 1b: shared app-launch coordinator `GameRootViewModel<Route>`.
        // `MinesweeperUI.MinesweeperRootViewModel` is a typealias over it.
        .package(name: "GameAppKit", path: "../GameAppKit"),
        // #530: MinesweeperUITests offline-hub fakes conform PersistenceProtocol,
        // which uses `Mode` / `GameSessionSnapshot` from SudokuCoreKit. Already
        // an indirect dep via PersistenceKit; promoted to direct so MinesweeperUITests
        // can `import SudokuGameState` / `import SudokuEngine` under InternalImportsByDefault.
        .package(name: "SudokuCoreKit", path: "../SudokuCoreKit"),
        // #278 Tier-1 Phase 2b: snapshot baselines for the themed MS board.
        // Same version pin as SudokuKit/Package.swift.
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
        // #178: swift-issue-reporting (`IssueReporting`) for invariant reporting
        // in MinesweeperUI. Transitive via swift-snapshot-testing (1.9.0);
        // promoted to direct dep. `from: "1.9.0"` matches resolved — no churn.
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.9.0"),
        // #750: shared ASC-screenshot render machinery (test-only), consumed by
        // MinesweeperUITests. See `docs/foundations.md` for the extraction rationale.
        .package(name: "GameTestSupportKit", path: "../GameTestSupportKit"),
    ],
    targets: productionTargets + testTargets,
    swiftLanguageModes: [.v6]
)
