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
