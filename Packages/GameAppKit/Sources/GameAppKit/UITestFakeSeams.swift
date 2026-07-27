// UITestFakeSeams — DEBUG-only, launch-arg-gated fakes proving the
// scenePhase-driven foreground re-poll wiring (#931) for two sites:
// `ReminderSettingsSection` (SettingsUI) and `BannerSlotView`
// (MonetizationUI). Wired into the live stack by `makeGameAppCore` only when
// the matching `UITestLaunchArg` is present; every non-uitest launch (incl.
// every Release build, via the `#if DEBUG` guard around this whole file)
// gets the real seams unchanged.
//
// Shared shape: each fake reports one answer until the process is observed
// entering the background (`UIApplication.didEnterBackgroundNotification`,
// iOS-only), then permanently flips to a different answer. `.task` never
// re-fires on foreground return (only on identity change — see
// swiftui-interaction-footguns), so ANY number of launch-time polls see the
// pre-flip answer; only a poll that happens AFTER a real background→
// foreground cycle can observe the post-flip answer. The only code path that
// can produce such a poll is the `.onChange(of: scenePhase)` hook under
// test — dropping that hook, or inverting its `== .active` guard, leaves the
// pre-flip answer forever and the corresponding E2E assertion times out.

#if DEBUG

internal import Foundation
internal import Reminders
internal import MonetizationCore
internal import GameCenterClient
internal import SudokuEngine
internal import SudokuGameState
internal import Persistence
#if os(iOS)
internal import UIKit
#endif

// MARK: - Reminder fake (ReminderSettingsSection, #929/#931)

/// Reports `.denied` until the process is observed entering the background,
/// then `.authorized`. See file header for the discrimination rationale.
actor UITestFlipOnBackgroundNotificationAuthorizing: NotificationAuthorizing {
    private var hasBackgrounded = false

    func markBackgrounded() {
        hasBackgrounded = true
    }

    func currentStatus() async -> ReminderAuthStatus {
        hasBackgrounded ? .authorized : .denied
    }

    func requestAuthorization(provisional: Bool) async -> ReminderAuthStatus {
        await currentStatus()
    }
}

// MARK: - Ad gate fake (BannerSlotView, #341/#931)

/// Error thrown by `UITestFlipOnBackgroundAdGateStateStore.loadState()`
/// before the process has been observed entering the background.
enum UITestAdGateFakeError: Error {
    case notYetBackgrounded
}

/// Throws `notYetBackgrounded` from `loadState()` until the process is
/// observed entering the background, then returns an always-open gate state
/// (no purchase, no dismissal, ancient `firstLaunchAt`).
///
/// Relies on `AdGate.currentState()`'s caching behavior: a THROWING
/// `loadState()` call never populates `AdGate`'s private `cachedState`
/// (only a successful load does), so every `shouldShowBanner` poll keeps
/// retrying the store until this fake starts succeeding — unlike a plain
/// state flip (e.g. toggling `dismissedDate`), which `AdGate` would cache
/// away after its first (pre-background) read and never re-consult. See
/// `AdGate.currentState()` for the exact caching logic this depends on.
final actor UITestFlipOnBackgroundAdGateStateStore: AdGateStateStore {
    private var hasBackgrounded = false

    func markBackgrounded() {
        hasBackgrounded = true
    }

    func loadState() async throws -> AdGateState {
        guard hasBackgrounded else { throw UITestAdGateFakeError.notYetBackgrounded }
        return AdGateState(firstLaunchAt: .distantPast)
    }

    func saveState(_ state: AdGateState) async throws {
        // No-op: this fake only needs to discriminate the repoll hook via
        // `loadState()`'s throw→succeed flip. `AdGate`'s own dismiss/purchase
        // mutation paths aren't exercised by the #931 E2E scenario.
    }
}

/// Minimal `AdProvider` fake so the #931 ad-gate E2E case never touches the
/// real AdMob SDK or network. Always reports `.loaded` once asked — the
/// discriminating signal for that test is the ad GATE (open/closed, via
/// `UITestFlipOnBackgroundAdGateStateStore` above), not the provider status.
actor UITestNoopAdProvider: AdProvider {
    func initialize() async throws {}

    var bannerStatus: AdBannerStatus {
        .loaded(AdBannerHandle())
    }

    func refreshBanner() async throws {}

    func dispose(handle: AdBannerHandle) async {}
}

// MARK: - Game Center signed-out fake (GC-SIGNED-OUT-ALERT N14, #935 batch 4)

/// Forces a genuinely `.unauthenticated` result from `authenticate()` so
/// `GameRootViewModel.bootstrap()`'s `self.authState = try await
/// gameCenter.authenticate()` lands on `.unauthenticated` without a throw —
/// see that call site for why a returned degraded state (rather than an
/// error) is the more honest shape here. Every other protocol member is an
/// inert no-op / benign default: `presentGameCenterOrAlert`'s signed-out
/// guard means the Home leaderboard card and the Settings GC row never reach
/// GameKit while this fake is installed, so nothing beyond `authenticate()`
/// is exercised by the N14 E2E flow.
struct UITestSignedOutGameCenterClient: GameCenterClient {
    func authenticate() async throws -> GameCenterAuthState {
        .unauthenticated
    }

    func authStateUpdates() async -> AsyncStream<GameCenterAuthState> {
        AsyncStream { continuation in continuation.finish() }
    }

    func submitScore(
        puzzleId: String,
        elapsedSeconds: Int,
        leaderboardKind: LeaderboardKind
    ) async throws {}

    func submitScore(leaderboardId: String, elapsedSeconds: Int) async throws {}

    func reportAchievement(_ achievement: AchievementProgress) async throws {}

    func fetchLeaderboardSlice(
        leaderboardId: String,
        scope: LeaderboardScope,
        aroundLocalPlayer: Bool,
        limit: Int
    ) async throws -> LeaderboardSlice {
        LeaderboardSlice(
            leaderboardId: leaderboardId,
            scope: scope,
            entries: [],
            totalPlayerCount: 0,
            fetchedAt: .distantPast
        )
    }

    func friendsAuthorizationStatus() async -> FriendsAuthStatus {
        .notDetermined
    }

    func requestFriendsAuthorization() async throws -> FriendsAuthStatus {
        .notDetermined
    }
}

// MARK: - Clear-cache failure fake (SettingsViewModel, CLEAR-CACHE-DIALOG N19, #935 batch 5)

/// Error thrown by `UITestClearCacheFailPersistence.deleteAbandoned` — the
/// N19 discriminating signal that flips `SettingsViewModel.clearCache()`
/// into its failure-toast branch.
enum UITestClearCacheFakeError: Error {
    case deleteFailed
}

/// Minimal zero-IO `PersistenceProtocol` conformer reporting ONE synthetic
/// in-progress saved game (so `SettingsViewModel.clearCache()`'s Storage row
/// + confirmation dialog are reachable and `resumeCandidate` is non-nil) and
/// THROWING from `deleteAbandoned` so the CLEAR-CACHE-DIALOG failure-toast
/// path fires deterministically. Every other member returns a safe empty
/// default — mirrors `PersistenceTesting.FakePersistence`'s minimal shape;
/// GameAppKit's production code can't depend on that Testing-only target, so
/// this DEBUG-only fake is its own conformer instead of reusing it.
struct UITestClearCacheFailPersistence: PersistenceProtocol {
    private static let syntheticSummary = SavedGameSummary(
        recordName: "uitest-clear-cache-fail",
        puzzleId: "uitest-clear-cache-fail",
        mode: .practice,
        difficulty: .easy,
        lastModifiedAt: .distantPast,
        elapsedSeconds: 0,
        status: "inProgress",
        generatorVersion: 1
    )

    func bootstrap() async throws {}

    func latestInProgress() async throws -> SavedGameSummary? { Self.syntheticSummary }

    func loadOrCreate(
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> GameSessionSnapshot {
        throw PersistenceError.zoneNotProvisioned
    }

    func save(
        _ snapshot: GameSessionSnapshot,
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws {}

    func markCompleted(_ summary: SavedGameSummary) async throws {}

    /// The N19 discriminating throw — `SettingsViewModel.clearCache()`'s
    /// catch branch fires the "Couldn't clear cache" failure toast instead
    /// of the success path.
    func deleteAbandoned(recordName: String) async throws {
        throw UITestClearCacheFakeError.deleteFailed
    }

    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> { [] }

    func fetchCompletedDailyIdsByDay() async throws -> [String: Set<String>] { [:] }

    func fetchPersonalRecord(
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> PersonalRecord {
        PersonalRecord(
            recordName: "",
            mode: .daily,
            difficulty: .easy,
            bestTimeSeconds: nil,
            totalTimeSeconds: 0,
            completedCount: 0,
            lastUpdatedAt: Date(timeIntervalSince1970: 0),
            completedPuzzleIds: []
        )
    }

    func upsertPersonalRecord(_ record: PersonalRecord) async throws {}
}

// MARK: - Scripted IAP fake (RemoveAdsRow, IAP-PURCHASE cancel/fail/pending N22, #935 batch 5)

/// Consumes a fixed script of `IAPPurchaseResult`s, one per `purchase()`
/// call, so ONE E2E test can walk all three `purchaseRemoveAds()` branches
/// (cancel → fail → pending) without the real StoreKit 2 payment sheet
/// (never driven by this repo's E2E suite — see
/// `MonetizationStateController.purchaseRemoveAds()`). Once the script is
/// exhausted, further calls keep repeating the LAST scripted result rather
/// than crashing, so a stray extra tap stays harmless.
actor UITestScriptedIAPClient: IAPClient {
    private var remaining: [IAPPurchaseResult]

    init(
        script: [IAPPurchaseResult] = [
            .userCancelled,
            .failed(reason: "uitest scripted failure"),
            .pending,
        ]
    ) {
        self.remaining = script
    }

    func availableProducts() async throws -> [IAPProduct] { [] }

    func purchase(_ productId: String) async throws -> IAPPurchaseResult {
        guard remaining.count > 1 else {
            return remaining.first ?? .failed(reason: "uitest: script exhausted with no results")
        }
        return remaining.removeFirst()
    }

    // #950 (N23 follow-up): always empty — models "nothing entitled" so the
    // restore-with-nothing-to-restore E2E test can assert the info toast
    // (`monetization.toast.info`) fires instead of the false "Purchases
    // restored" success claim. No separate script needed: an empty restore
    // result is the ONLY outcome this fake ever needs to produce.
    func restorePurchases() async throws -> [IAPProduct] { [] }

    nonisolated func purchaseUpdates() -> AsyncStream<IAPPurchaseEvent> {
        AsyncStream { continuation in continuation.finish() }
    }
}

// MARK: - Background observation

/// Registers the one `UIApplication.didEnterBackgroundNotification` observer
/// a fake above needs to flip. iOS-only (no such notification off-device);
/// a no-op on macOS since these launch args target the Simulator only.
@MainActor
func installUITestBackgroundFlipObserver(onBackground: @escaping @Sendable () -> Void) {
    #if os(iOS)
    NotificationCenter.default.addObserver(
        forName: UIApplication.didEnterBackgroundNotification,
        object: nil,
        queue: .main
    ) { _ in
        onBackground()
    }
    #endif
}

#endif
