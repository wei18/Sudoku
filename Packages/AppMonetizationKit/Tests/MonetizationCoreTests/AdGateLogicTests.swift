// swiftlint:disable identifier_name

import Foundation
import Testing
@testable import MonetizationCore
import MonetizationTesting

// Test-only helpers ----------------------------------------------------------

private let utcCalendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
}()

/// A deterministic "first launch" anchor: 2026-01-01 00:00:00 UTC.
private let firstLaunch: Date = {
    var components = DateComponents()
    components.year = 2026
    components.month = 1
    components.day = 1
    components.timeZone = TimeZone(identifier: "UTC")
    return utcCalendar.date(from: components)!
}()

private func days(_ n: Double, after base: Date) -> Date {
    base.addingTimeInterval(n * 86_400)
}

private func freshGate(
    state: AdGateState = AdGateState(firstLaunchAt: firstLaunch)
) async -> (AdGate, FakeAdGateStateStore) {
    let store = FakeAdGateStateStore(initial: state)
    let gate = AdGate(store: store, calendar: utcCalendar)
    return (gate, store)
}

// Suite ---------------------------------------------------------------------

@Suite("AdGate — frequency policy")
struct AdGateLogicTests {

    // MARK: Grace period

    @Test func day0SuppressesDuringGrace() async {
        let (gate, _) = await freshGate()
        let shown = await gate.shouldShowBanner(now: firstLaunch)
        #expect(shown == false)
    }

    @Test func day6StillInGrace() async {
        let (gate, _) = await freshGate()
        let shown = await gate.shouldShowBanner(now: days(6, after: firstLaunch))
        #expect(shown == false)
    }

    @Test func day7BoundaryReleasesGrace() async {
        let (gate, _) = await freshGate()
        let shown = await gate.shouldShowBanner(now: days(7, after: firstLaunch))
        #expect(shown == true)
    }

    @Test func justBeforeDay7BoundaryStillInGrace() async {
        let (gate, _) = await freshGate()
        // 6 days 23:59:59 — one second short of the 7-day boundary.
        let nearBoundary = firstLaunch.addingTimeInterval(7 * 86_400 - 1)
        let shown = await gate.shouldShowBanner(now: nearBoundary)
        #expect(shown == false)
    }

    // MARK: Dismissed-today rule

    @Test func dismissedTodaySuppresses() async {
        let now = days(10, after: firstLaunch)
        let state = AdGateState(
            firstLaunchAt: firstLaunch,
            dismissedDate: utcCalendar.startOfDay(for: now)
        )
        let (gate, _) = await freshGate(state: state)
        let shown = await gate.shouldShowBanner(now: now)
        #expect(shown == false)
    }

    @Test func dismissedYesterdayDoesNotSuppress() async {
        let yesterday = days(9, after: firstLaunch)
        let today = days(10, after: firstLaunch)
        let state = AdGateState(
            firstLaunchAt: firstLaunch,
            dismissedDate: utcCalendar.startOfDay(for: yesterday)
        )
        let (gate, _) = await freshGate(state: state)
        let shown = await gate.shouldShowBanner(now: today)
        #expect(shown == true)
    }

    // MARK: Purchased flag

    @Test func purchasedRemoveAdsAlwaysSuppresses() async {
        let state = AdGateState(
            firstLaunchAt: firstLaunch,
            hasPurchasedRemoveAds: true
        )
        let (gate, _) = await freshGate(state: state)
        // Far past grace, no dismissal — purchase still wins.
        let shown = await gate.shouldShowBanner(now: days(365, after: firstLaunch))
        #expect(shown == false)
    }

    @Test func purchaseTrumpsAllOtherPredicates() async {
        let now = days(10, after: firstLaunch)
        let state = AdGateState(
            firstLaunchAt: firstLaunch,
            dismissedDate: nil,
            hasPurchasedRemoveAds: true
        )
        let (gate, _) = await freshGate(state: state)
        #expect(await gate.shouldShowBanner(now: now) == false)
    }

    // MARK: Mutations persist via store

    @Test func recordBannerShownPersistsCalendarDayStart() async {
        let (gate, store) = await freshGate()
        let now = days(10, after: firstLaunch).addingTimeInterval(3600 * 13)  // 13:00 on day 10
        await gate.recordBannerShown(now: now)
        let saved = await store.peekState()
        #expect(saved?.lastShownDate == utcCalendar.startOfDay(for: now))
        #expect(await store.saveCallCount == 1)
    }

    @Test func recordBannerDismissedPersistsAndGates() async {
        let (gate, store) = await freshGate()
        let now = days(10, after: firstLaunch)
        await gate.recordBannerDismissed(now: now)
        let saved = await store.peekState()
        #expect(saved?.dismissedDate == utcCalendar.startOfDay(for: now))
        // And the gate now reports suppressed for the rest of today.
        #expect(await gate.shouldShowBanner(now: now) == false)
    }

    @Test func recordPurchaseFlipsFlagAndNeverReverses() async {
        let (gate, store) = await freshGate()
        await gate.recordPurchase()
        #expect(await store.peekState()?.hasPurchasedRemoveAds == true)
        // No reverse API; even calling other mutations afterwards keeps it true.
        await gate.recordBannerShown(now: days(8, after: firstLaunch))
        #expect(await store.peekState()?.hasPurchasedRemoveAds == true)
    }

    // MARK: State caching

    @Test func stateLoadsOnceThenServesFromCache() async {
        let (gate, store) = await freshGate()
        _ = await gate.shouldShowBanner(now: firstLaunch)
        _ = await gate.shouldShowBanner(now: days(8, after: firstLaunch))
        _ = await gate.shouldShowBanner(now: days(9, after: firstLaunch))
        #expect(await store.loadCallCount == 1)
    }

    // MARK: Calendar timezone independence

    @Test func dismissedTodayHonorsInjectedCalendarTimezone() async {
        // Same wall-clock instant, but two different calendar-day perceptions:
        // - UTC: 2026-01-11 23:00 → day 10 still
        // - Pacific (UTC-8): 2026-01-11 15:00 → still day 10
        // Verify UTC calendar treats 23:00 UTC and 23:30 UTC on the same day
        // as same-day for dismissal.
        let dayStart = days(10, after: firstLaunch)
        let dismissedAt = dayStart.addingTimeInterval(23 * 3600)  // 23:00 UTC day 10
        let queryAt = dayStart.addingTimeInterval(23.5 * 3600)    // 23:30 UTC day 10
        let state = AdGateState(
            firstLaunchAt: firstLaunch,
            dismissedDate: utcCalendar.startOfDay(for: dismissedAt)
        )
        let (gate, _) = await freshGate(state: state)
        #expect(await gate.shouldShowBanner(now: queryAt) == false)
    }
}
