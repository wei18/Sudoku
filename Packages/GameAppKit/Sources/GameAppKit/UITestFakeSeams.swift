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
        difficulty: Difficulty,
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
