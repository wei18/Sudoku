// UITestAlwaysOpenAdGateStateStoreTests — #1024 (PM-approved) fake contract.
//
// The whole fake is `#if DEBUG` (defined in UITestFakeSeams.swift), so this
// suite is too. Two things this arg's design depends on, both worth pinning
// directly rather than trusting by inspection alone (mirrors the pattern of
// `UITestSignedOutGameCenterClientTests` / `UITestScriptedIAPClientTests` —
// test the FAKE's behavior; the `#if DEBUG` + `ProcessInfo.arguments.contains`
// gating shape itself is the same, already-proven wiring every prior
// `UITestLaunchArg` uses, not re-tested per-arg):
//
//   1. The fake, run through a REAL `AdGate`, actually opens the gate — not
//      just "the struct's fields look right", but the end effect
//      `-uitest-open-ad-gate` exists for.
//   2. `resolveAdProvider` is unaffected by this arg's existence — it still
//      returns whatever `makeLive()` produces, proving the PM's "never
//      touches the provider resolution" condition behaviorally, not just by
//      the `git diff` showing zero changes to that function's body.

#if DEBUG

import Foundation
import Testing
import MonetizationCore
@testable import GameAppKit

@Suite("UITestAlwaysOpenAdGateStateStore (#1024)")
struct UITestAlwaysOpenAdGateStateStoreTests {

    @Test("loadState reports an unconditionally-open state: no purchase, no dismissal, no tamper baseline")
    func loadStateReportsOpenState() async throws {
        let state = try await UITestAlwaysOpenAdGateStateStore().loadState()

        #expect(state.hasPurchasedRemoveAds == false)
        #expect(state.dismissedDate == nil)
        #expect(state.lastSeenWallClock == nil)
        #expect(
            state.firstLaunchAt < Date().addingTimeInterval(-365 * 86_400),
            "firstLaunchAt must be far enough in the past that a future non-zero grace period can't suppress the banner"
        )
    }

    @Test("wired into a real AdGate, the fake actually opens shouldShowBanner")
    func realAdGateOpensWithThisFake() async {
        let gate = AdGate(store: UITestAlwaysOpenAdGateStateStore())

        let allowed = await gate.shouldShowBanner(now: Date())

        #expect(allowed == true, "the fake must produce an open gate through AdGate's real decision logic, not just look open on paper")
    }

    @MainActor
    @Test("resolveAdProvider is unaffected by -uitest-open-ad-gate — the live provider path is untouched")
    func resolveAdProviderStillReturnsMakeLiveResult() {
        struct MarkerProvider: AdProvider {
            func initialize() async throws {}
            var bannerStatus: AdBannerStatus { get async { .notInitialized } }
            func refreshBanner() async throws {}
            func dispose(handle: AdBannerHandle) async {}
        }

        // This test process's own launch arguments never contain
        // `-uitest-fake-ad-gate-repoll` (the only arg `resolveAdProvider`
        // reads), so `makeLive()` must always win here — proving the
        // function's live-provider path is reachable and untouched by
        // #1024's new arg, which `resolveAdProvider` doesn't even reference.
        let provider = resolveAdProvider { MarkerProvider() }

        #expect(provider is MarkerProvider, "resolveAdProvider must still hand back makeLive()'s result unchanged")
    }
}

#endif
