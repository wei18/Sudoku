// AdGateLayoutHintTests — #723 synchronous layout-reservation hint.
//
// `AdGate.lastKnownShouldShowBanner` is the session cache `BannerSlotView`
// reads at init to reserve its 50pt from the first layout. Contract:
//   - `nil` before the session's first `shouldShowBanner` resolution;
//   - mirrors the latest resolution afterwards (allow AND deny);
//   - flips to `false` eagerly on `recordBannerDismissed` / `recordPurchase`
//     so a slot mounted right after either never over-reserves on a stale
//     `true`.

import Foundation
import Testing
@testable import MonetizationCore
import MonetizationTesting

private let utcCalendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
}()

/// Deterministic anchor: 2026-01-01 00:00:00 UTC (mirrors AdGateLogicTests).
private let firstLaunch: Date = {
    var components = DateComponents()
    components.year = 2026
    components.month = 1
    components.day = 1
    components.timeZone = TimeZone(identifier: "UTC")
    return utcCalendar.date(from: components)!
}()

@Suite("AdGate — #723 lastKnownShouldShowBanner layout hint")
struct AdGateLayoutHintTests {

    private func makeGate(purchased: Bool = false) -> AdGate {
        let store = FakeAdGateStateStore(
            initial: AdGateState(
                firstLaunchAt: firstLaunch,
                hasPurchasedRemoveAds: purchased
            )
        )
        return AdGate(store: store, calendar: utcCalendar)
    }

    @Test func hintIsNilBeforeFirstResolution() {
        let gate = makeGate()
        #expect(gate.lastKnownShouldShowBanner == nil)
    }

    @Test func hintMirrorsAllowResolution() async {
        let gate = makeGate()
        let shown = await gate.shouldShowBanner(now: firstLaunch)
        #expect(shown == true)
        #expect(gate.lastKnownShouldShowBanner == true)
    }

    @Test func hintMirrorsDenyResolution() async {
        let gate = makeGate(purchased: true)
        let shown = await gate.shouldShowBanner(now: firstLaunch)
        #expect(shown == false)
        #expect(gate.lastKnownShouldShowBanner == false)
    }

    @Test func dismissFlipsHintToFalseEagerly() async {
        let gate = makeGate()
        _ = await gate.shouldShowBanner(now: firstLaunch)
        #expect(gate.lastKnownShouldShowBanner == true)
        await gate.recordBannerDismissed(now: firstLaunch)
        #expect(gate.lastKnownShouldShowBanner == false)
    }

    @Test func purchaseFlipsHintToFalseEagerly() async {
        let gate = makeGate()
        _ = await gate.shouldShowBanner(now: firstLaunch)
        #expect(gate.lastKnownShouldShowBanner == true)
        await gate.recordPurchase()
        #expect(gate.lastKnownShouldShowBanner == false)
    }

    @Test func dayRolloverResolutionReopensHintAfterDismiss() async {
        let gate = makeGate()
        await gate.recordBannerDismissed(now: firstLaunch)
        #expect(gate.lastKnownShouldShowBanner == false)
        // Next calendar day: the real resolution allows again and the hint
        // follows it (repollGate path).
        let nextDay = firstLaunch.addingTimeInterval(86_400)
        let shown = await gate.shouldShowBanner(now: nextDay)
        #expect(shown == true)
        #expect(gate.lastKnownShouldShowBanner == true)
    }
}
