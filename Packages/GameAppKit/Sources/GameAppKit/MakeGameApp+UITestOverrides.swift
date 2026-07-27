// MakeGameApp+UITestOverrides — #931 launch-arg-gated seam swaps, extracted
// out of `makeGameAppCore` (MakeGameApp.swift) to keep that function's
// cyclomatic complexity and this pair of files' line counts under the
// SwiftLint ceilings. Every helper here is a plain pass-through to its
// `fallback` / `makeLive` argument outside DEBUG (and on every DEBUG launch
// that doesn't carry the matching `UITestLaunchArg`), so production wiring
// is byte-identical to before #931 unless a uitest arg is present.

internal import Foundation
internal import MonetizationCore
internal import Reminders
internal import GameCenterClient
internal import Persistence

/// #931: resolves the `AdGateStateStore` `AdGate` reads from. Under
/// `-uitest-fake-ad-gate-repoll` (DEBUG only), swaps in
/// `UITestFlipOnBackgroundAdGateStateStore` and registers its background-flip
/// observer so the E2E suite can pin `BannerSlotView`'s scenePhase repoll
/// hook (`repollGate()`) deterministically. See `UITestFakeSeams.swift` for
/// why a THROWING fake (rather than a plain state flip) is required to defeat
/// `AdGate.currentState()`'s caching.
@MainActor
func resolveAdGateStore(fallback: any AdGateStateStore) -> any AdGateStateStore {
    #if DEBUG
    guard ProcessInfo.processInfo.arguments.contains(UITestLaunchArg.fakeAdGateRepoll) else {
        return fallback
    }
    let fake = UITestFlipOnBackgroundAdGateStateStore()
    installUITestBackgroundFlipObserver { Task { await fake.markBackgrounded() } }
    return fake
    #else
    return fallback
    #endif
}

/// #931: resolves the `AdProvider` `BannerSlotView` renders from. Under
/// `-uitest-fake-ad-gate-repoll` (DEBUG only), swaps in `UITestNoopAdProvider`
/// so the paired E2E test never touches the AdMob SDK or network. `makeLive`
/// is only invoked when the fake path is NOT taken, so the real
/// AdMob-unit-ID guard (`preconditionFailure` on a missing/unresolved
/// `GADBannerUnitID`) never runs under the uitest arg.
@MainActor
func resolveAdProvider(makeLive: () -> any AdProvider) -> any AdProvider {
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains(UITestLaunchArg.fakeAdGateRepoll) {
        return UITestNoopAdProvider()
    }
    #endif
    return makeLive()
}

/// #931: resolves the `NotificationAuthorizing` `ReminderSettingsModel` /
/// `ReminderPrimerCoordinator` read from. Under `-uitest-fake-reminder-repoll`
/// (DEBUG only), swaps in `UITestFlipOnBackgroundNotificationAuthorizing`
/// (denied until the process is observed entering the background, then
/// authorized) and registers its background-flip observer so the E2E suite
/// can pin `ReminderSettingsSection`'s scenePhase repoll hook
/// deterministically. `reminderScheduler` is never faked — only the
/// permission-status seam.
@MainActor
func resolveReminderAuthorizer(fallback: any NotificationAuthorizing) -> any NotificationAuthorizing {
    #if DEBUG
    guard ProcessInfo.processInfo.arguments.contains(UITestLaunchArg.fakeReminderRepoll) else {
        return fallback
    }
    let fake = UITestFlipOnBackgroundNotificationAuthorizing()
    installUITestBackgroundFlipObserver { Task { await fake.markBackgrounded() } }
    return fake
    #else
    return fallback
    #endif
}

/// #935 batch 4: resolves the `GameCenterClient` `GameRootViewModel.bootstrap()`
/// authenticates against. Under `-uitest-gc-signed-out` (DEBUG only), swaps in
/// `UITestSignedOutGameCenterClient` so `authState` deterministically lands on
/// `.unauthenticated`, letting the N14 GC-SIGNED-OUT-ALERT E2E flow run
/// without depending on the live GameKit handshake's (nondeterministic) sim
/// behavior. `makeLive` is `@autoclosure` (rather than `resolveAdProvider`'s
/// explicit trailing closure) so the call site stays a single expression —
/// it is still only evaluated when the fake path is NOT taken.
@MainActor
func resolveGameCenterClient(makeLive: @autoclosure () -> any GameCenterClient) -> any GameCenterClient {
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains(UITestLaunchArg.gcSignedOut) {
        return UITestSignedOutGameCenterClient()
    }
    #endif
    return makeLive()
}

/// #935 batch 5: resolves `ATTPrimerCoordinator`'s `isNotDetermined` touch
/// point. Under `-uitest-att-primer` (DEBUG only), forces `true` so the
/// ATT-PRIMER-DECLINE E2E flow (N15) can present the sheet deterministically
/// regardless of the simulator's real (once-per-install) ATT status.
@MainActor
func resolveATTIsNotDetermined(
    fallback: @escaping @Sendable () async -> Bool
) -> @Sendable () async -> Bool {
    #if DEBUG
    guard ProcessInfo.processInfo.arguments.contains(UITestLaunchArg.attPrimer) else {
        return fallback
    }
    return { true }
    #else
    return fallback
    #endif
}

/// #935 batch 5: resolves `ATTPrimerCoordinator`'s `requestSystemPrompt`
/// touch point. Under `-uitest-att-primer` (DEBUG only), swaps in a no-op so
/// "Continue" never fires the real system ATT dialog during E2E — N15 only
/// exercises "Not now", but keeping this seam paired with the one above
/// avoids leaving the coordinator half-faked.
@MainActor
func resolveATTRequestSystemPrompt(
    fallback: @escaping @Sendable () async -> Void
) -> @Sendable () async -> Void {
    #if DEBUG
    guard ProcessInfo.processInfo.arguments.contains(UITestLaunchArg.attPrimer) else {
        return fallback
    }
    return {}
    #else
    return fallback
    #endif
}

/// #935 batch 5: resolves the `PersistenceProtocol` conformer wired into
/// `GameDeps`/`GameRootViewModel`. Under `-uitest-clear-cache-fail` (DEBUG
/// only), swaps in `UITestClearCacheFailPersistence` so the CLEAR-CACHE-DIALOG
/// failure-toast E2E flow (N19) can be exercised deterministically — a real
/// CloudKit delete failure can't be forced on demand from a
/// signed-in-but-offline simulator.
@MainActor
func resolvePersistence(fallback: any PersistenceProtocol) -> any PersistenceProtocol {
    #if DEBUG
    guard ProcessInfo.processInfo.arguments.contains(UITestLaunchArg.clearCacheFail) else {
        return fallback
    }
    return UITestClearCacheFailPersistence()
    #else
    return fallback
    #endif
}

/// #935 batch 5: resolves the `IAPClient` `MonetizationStateController`
/// drives. Under `-uitest-iap-script` (DEBUG only), swaps in
/// `UITestScriptedIAPClient` so the IAP-PURCHASE cancel/fail/pending negative
/// flow (N22) can walk all three `purchaseRemoveAds()` branches
/// deterministically — the real `LiveStoreKit2IAPClient` requires the
/// StoreKit 2 payment sheet, which this repo's E2E suite never drives.
/// `makeLive` is `@autoclosure` (mirrors `resolveGameCenterClient`) so the
/// call site stays a single expression; only evaluated when the fake path is
/// NOT taken.
@MainActor
func resolveIAPClient(makeLive: @autoclosure () -> any IAPClient) -> any IAPClient {
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains(UITestLaunchArg.iapScript) {
        return UITestScriptedIAPClient()
    }
    #endif
    return makeLive()
}
