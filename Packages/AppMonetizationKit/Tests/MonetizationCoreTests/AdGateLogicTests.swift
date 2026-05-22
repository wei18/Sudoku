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

    // M4: timezone-shift / cross-date-line dismissal
    //
    // Scenario: user dismisses the banner near the end of a UTC day, then
    // queries (e.g. via wake from background / pull-to-refresh) after the
    // UTC day has rolled over. Even though the wall-clock difference is
    // small (16h-23.5h = -7.5h, but in absolute terms it is +16.5h forward),
    // the dismissal landed on a *different* calendar day than the query —
    // so the gate should NOT suppress the banner.
    @Test func dismissedTodayAcrossDateLineCrossing() async {
        // Calendar fixed to UTC so the test is timezone-host-independent.
        var dismissComponents = DateComponents()
        dismissComponents.year = 2026
        dismissComponents.month = 5
        dismissComponents.day = 20
        dismissComponents.hour = 23
        dismissComponents.minute = 30
        dismissComponents.timeZone = TimeZone(identifier: "UTC")
        let dismissedAt = utcCalendar.date(from: dismissComponents)!

        var queryComponents = DateComponents()
        queryComponents.year = 2026
        queryComponents.month = 5
        queryComponents.day = 21
        queryComponents.hour = 16
        queryComponents.minute = 0
        queryComponents.timeZone = TimeZone(identifier: "UTC")
        let queryAt = utcCalendar.date(from: queryComponents)!

        let state = AdGateState(
            firstLaunchAt: firstLaunch,
            dismissedDate: utcCalendar.startOfDay(for: dismissedAt)
        )
        let (gate, _) = await freshGate(state: state)
        // Dismissed on 2026-05-20 UTC; query is on 2026-05-21 UTC — banner
        // CAN show (the dismissed-today gate no longer applies).
        #expect(await gate.shouldShowBanner(now: queryAt) == true)
    }

    // MARK: Clock-tamper defense (M5 / design.md §How.3.1)

    @Test func clockMovedBackwardsRefusesGraceAdvance() async {
        // Use a far-past `firstLaunchAt` so the 7-day grace rule (rule #2)
        // passes for the rewound `now`, ensuring the M5 tamper-guard branch
        // (rule #4) is the one that fires.
        //
        //   firstLaunchAt          = 2024-01-01  (>1y before rewound)
        //   lastSeenWallClock      = 2026-05-21T12:00:00Z
        //   now (rewound)          = 2026-01-01  (~5 months back, far beyond 24h)
        //
        // Verification: temporarily commenting out the `if let lastSeen…`
        // block in `AdGate.shouldShowBanner` makes this test RED (returns
        // true once the guard is gone). Restoring the guard makes it GREEN.
        var firstLaunchPastComponents = DateComponents()
        firstLaunchPastComponents.year = 2024
        firstLaunchPastComponents.month = 1
        firstLaunchPastComponents.day = 1
        firstLaunchPastComponents.timeZone = TimeZone(identifier: "UTC")
        let firstLaunchFarPast = utcCalendar.date(from: firstLaunchPastComponents)!

        var baselineComponents = DateComponents()
        baselineComponents.year = 2026
        baselineComponents.month = 5
        baselineComponents.day = 21
        baselineComponents.hour = 12
        baselineComponents.timeZone = TimeZone(identifier: "UTC")
        let baseline = utcCalendar.date(from: baselineComponents)!

        var rewoundComponents = DateComponents()
        rewoundComponents.year = 2026
        rewoundComponents.month = 1
        rewoundComponents.day = 1
        rewoundComponents.timeZone = TimeZone(identifier: "UTC")
        let rewound = utcCalendar.date(from: rewoundComponents)!

        let state = AdGateState(
            firstLaunchAt: firstLaunchFarPast,
            lastSeenWallClock: baseline
        )
        let (gate, _) = await freshGate(state: state)
        // `rewound` is well past `firstLaunchAt + 7d` (>1 year past grace),
        // so rule #2 PASSES. The clock-tamper guard (rule #4) refuses to
        // show — the user moved their clock back ~5 months.
        #expect(await gate.shouldShowBanner(now: rewound) == false)
    }

    @Test func clockToleranceWithin24hStillShows() async {
        // Same scenario, but only a 1h backwards delta — well inside the
        // 24h tolerance (covers DST / cross-timezone moves / NTP drift).
        var baselineComponents = DateComponents()
        baselineComponents.year = 2026
        baselineComponents.month = 5
        baselineComponents.day = 21
        baselineComponents.hour = 12
        baselineComponents.timeZone = TimeZone(identifier: "UTC")
        let baseline = utcCalendar.date(from: baselineComponents)!
        let oneHourEarlier = baseline.addingTimeInterval(-3600)

        let state = AdGateState(
            firstLaunchAt: firstLaunch,
            lastSeenWallClock: baseline
        )
        let (gate, _) = await freshGate(state: state)
        #expect(await gate.shouldShowBanner(now: oneHourEarlier) == true)
    }

    // MARK: M2 — persistence-error closure

    @Test func saveFailureSurfacesViaOnPersistenceError() async {
        // Wire a fake store that throws on save, plus a sink that records the
        // error. Verify the closure fires and that the in-memory cache still
        // reflects the attempted mutation (consistency invariant).
        struct StubError: Error, Equatable {}
        let store = FakeAdGateStateStore(
            initial: AdGateState(firstLaunchAt: firstLaunch)
        )
        await store.scriptSaveError(StubError())

        // `Mutex`-style capture via an actor — keeps `Sendable` clean.
        actor Sink {
            var captured: [String] = []
            func record(_ description: String) { captured.append(description) }
        }
        let sink = Sink()

        let gate = AdGate(
            store: store,
            calendar: utcCalendar,
            onPersistenceError: { error in
                Task { await sink.record(String(describing: error)) }
            }
        )
        await gate.recordBannerDismissed(now: days(10, after: firstLaunch))

        // Drain any pending sink work.
        await Task.yield()
        // Some platforms need a brief hop for the detached `Task` above.
        try? await Task.sleep(nanoseconds: 10_000_000)

        let captured = await sink.captured
        #expect(captured.count == 1)
        #expect(captured.first?.contains("StubError") == true)
    }

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
