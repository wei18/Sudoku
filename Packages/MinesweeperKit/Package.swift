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
            // protocol; `MinesweeperGameCenterDashboard` presents the native
            // GC modal. GameKit stays fully encapsulated inside GameCenterKit's
            // Live target — MinesweeperUI sees only the GameKit-free protocol.
            .product(name: "GameCenterClient", package: "GameCenterKit"),
            // #178: invariant-reporting tool — mirrors SudokuUI. `reportIssue(_:)`
            // surfaces impossible-state catches (fails tests, purple-warns in
            // #Preview, non-fatal in release). Deliberate restricted-import
            // allowance, not a replacement for ErrorReporter. See foundations.md §3.
            .product(name: "IssueReporting", package: "xctest-dynamic-overlay"),
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
            // MS monetization wire Phase 3 + U15 (2026-06-03). AdsAdMob wires
            // `LiveAdMobAdProvider` on iOS; on macOS `.live()` falls back to
            // `NoopAdProvider` from MonetizationCore (the AdMob SDK ships an
            // iOS-only xcframework).
            .product(name: "Persistence", package: "PersistenceKit"),
            // #261: `.preview()` wires `FakePersistence` (zero-IO) instead of
            // `LivePersistence` so any future Preview path that calls
            // bootstrap()/latestInProgress() stays trap-free. Production target
            // intentionally deps the Testing product — same pattern as Sudoku's
            // AppComposition (its FakePersistence ships via SudokuKitTesting).
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
            // Mirrors Sudoku's AppComposition (Live.swift / Preview.swift).
            .product(name: "GameCenterClient", package: "GameCenterKit"),
            .product(name: "GameCenterTesting", package: "GameCenterKit"),
            // #287: the shared local-notification reminder seam. `.live()` wires
            // `LiveReminderScheduler` / `LiveNotificationAuthorizer` (the only
            // files allowed to import `UserNotifications`) to drive the Settings
            // Reminders entry; the UI model/section come through GameShellUI.
            // Mirrors Sudoku's AppComposition RemindersKit wire.
            .product(name: "Reminders", package: "RemindersKit"),
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
            // #291: submit-on-win + leaderboard-card present tests inject the
            // shared `FakeGameCenterClient` to assert call shape.
            .product(name: "GameCenterClient", package: "GameCenterKit"),
            .product(name: "GameCenterTesting", package: "GameCenterKit"),
            // #278 Tier-1 Phase 2b: MS snapshot harness. Mirrors SudokuKit's
            // SudokuUITests snapshot dep — themed board baselines are the
            // Designer's visual-verification surface.
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            // #287: the SettingsView reminder-entry sentinel builds a
            // `ReminderSettingsModel` over the `Reminders` Noop conformers.
            .product(name: "Reminders", package: "RemindersKit"),
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
        // #278 Tier-1 Phase 2b: snapshot baselines for the themed MS board.
        // Same version pin as SudokuKit/Package.swift.
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
        // #178: swift-issue-reporting (`IssueReporting`) for invariant reporting
        // in MinesweeperUI. Transitive via swift-snapshot-testing (1.9.0);
        // promoted to direct dep. `from: "1.9.0"` matches resolved — no churn.
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.9.0"),
    ],
    targets: productionTargets + testTargets,
    swiftLanguageModes: [.v6]
)
