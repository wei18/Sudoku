import Testing
import Foundation
@testable import MonetizationCore
import MonetizationTesting

// MARK: - BannerReloadCoordinatorTests (#341)
//
// The reload seam: `BannerReloadCoordinator` re-evaluates `AdGate` and re-loads
// the provider banner when (and only when) the gate is open. This is what makes
// the documented `AdProvider.refreshBanner()` gate-reopen reload actually
// reachable from a re-poll trigger (scene activation / next-day) instead of
// staying gone until app relaunch.
//
// Remove-Ads safety is the headline invariant: a purchased user's gate returns
// false, so the coordinator must NEVER call `refreshBanner()` for them.

private let utcCalendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
}()

private let firstLaunch: Date = {
    var components = DateComponents()
    components.year = 2026
    components.month = 1
    components.day = 1
    components.timeZone = TimeZone(identifier: "UTC")
    return utcCalendar.date(from: components)!
}()

private func days(_ count: Double, after base: Date) -> Date {
    base.addingTimeInterval(count * 86_400)
}

private func makeGate(_ state: AdGateState) -> (AdGate, FakeAdGateStateStore) {
    let store = FakeAdGateStateStore(initial: state)
    let gate = AdGate(store: store, calendar: utcCalendar)
    return (gate, store)
}

@Suite("BannerReloadCoordinator — gate-aware reload seam (#341)")
struct BannerReloadCoordinatorTests {

    // MARK: Gate open → reloads

    @Test func reloadsWhenGateOpen() async throws {
        let handle = AdBannerHandle()
        let provider = FakeAdProvider(
            scripted: .init(statusSequence: [.loading, .loaded(handle)])
        )
        let (gate, _) = makeGate(AdGateState(firstLaunchAt: firstLaunch))
        let coordinator = BannerReloadCoordinator(adProvider: provider, adGate: gate)

        let status = try await coordinator.reloadIfGateOpen(now: days(10, after: firstLaunch))

        #expect(await provider.refreshCallCount == 1)
        #expect(status == .loaded(handle))
    }

    // MARK: Next-day gate reopen (the headline #341 case)

    @Test func reloadsAfterDismissOnNextCalendarDay() async throws {
        let handle = AdBannerHandle()
        let provider = FakeAdProvider(
            scripted: .init(statusSequence: [.loading, .loaded(handle)])
        )
        // Dismissed yesterday → gate is open again today.
        let yesterday = days(9, after: firstLaunch)
        let today = days(10, after: firstLaunch)
        let (gate, _) = makeGate(
            AdGateState(
                firstLaunchAt: firstLaunch,
                dismissedDate: utcCalendar.startOfDay(for: yesterday)
            )
        )
        let coordinator = BannerReloadCoordinator(adProvider: provider, adGate: gate)

        let status = try await coordinator.reloadIfGateOpen(now: today)

        #expect(await provider.refreshCallCount == 1)
        #expect(status == .loaded(handle))
    }

    // MARK: Dismissed today → gate closed → suppressed, NO reload

    @Test func doesNotReloadWhenDismissedToday() async throws {
        let provider = FakeAdProvider(scripted: .init(statusSequence: [.loaded(AdBannerHandle())]))
        let today = days(10, after: firstLaunch)
        let (gate, _) = makeGate(
            AdGateState(
                firstLaunchAt: firstLaunch,
                dismissedDate: utcCalendar.startOfDay(for: today)
            )
        )
        let coordinator = BannerReloadCoordinator(adProvider: provider, adGate: gate)

        let status = try await coordinator.reloadIfGateOpen(now: today)

        #expect(await provider.refreshCallCount == 0)
        #expect(status == .suppressed)
    }

    // MARK: Remove-Ads regression — purchased user NEVER reloads

    @Test func purchasedUserNeverReloads() async throws {
        let provider = FakeAdProvider(scripted: .init(statusSequence: [.loaded(AdBannerHandle())]))
        let (gate, _) = makeGate(
            AdGateState(firstLaunchAt: firstLaunch, hasPurchasedRemoveAds: true)
        )
        let coordinator = BannerReloadCoordinator(adProvider: provider, adGate: gate)

        // Even far past any window, on a fresh day, with no dismissal: purchase wins.
        let status = try await coordinator.reloadIfGateOpen(now: days(365, after: firstLaunch))

        #expect(await provider.refreshCallCount == 0)
        #expect(status == .suppressed)
    }

    @Test func purchasedUserNeverReloadsAcrossRepeatedRepolls() async throws {
        let provider = FakeAdProvider(scripted: .init(statusSequence: [.loaded(AdBannerHandle())]))
        let (gate, _) = makeGate(
            AdGateState(firstLaunchAt: firstLaunch, hasPurchasedRemoveAds: true)
        )
        let coordinator = BannerReloadCoordinator(adProvider: provider, adGate: gate)

        // Simulate many re-poll triggers (scene activations / day rolls).
        for day in 1...5 {
            let status = try await coordinator.reloadIfGateOpen(now: days(Double(day), after: firstLaunch))
            #expect(status == .suppressed)
        }
        #expect(await provider.refreshCallCount == 0)
    }

    // MARK: Refresh failure surfaces as .failed (not a crash, not suppressed)

    @Test func refreshFailureSurfacesFailedStatus() async throws {
        struct LoadError: Error {}
        let provider = FakeAdProvider(
            scripted: .init(statusSequence: [.loading], refreshThrows: LoadError())
        )
        let (gate, _) = makeGate(AdGateState(firstLaunchAt: firstLaunch))
        let coordinator = BannerReloadCoordinator(adProvider: provider, adGate: gate)

        let status = try await coordinator.reloadIfGateOpen(now: days(10, after: firstLaunch))

        #expect(await provider.refreshCallCount == 1)
        if case .failed = status {
            // expected
        } else {
            Issue.record("expected .failed, got \(status)")
        }
    }

    // MARK: Cancellation is not failure (#1058 PM 1, seam 2)

    @Test func cancelledRefreshThrowsCancellationInsteadOfFailed() async throws {
        let provider = FakeAdProvider(
            scripted: .init(statusSequence: [.loading], refreshThrows: CancellationError())
        )
        let (gate, _) = makeGate(AdGateState(firstLaunchAt: firstLaunch))
        let coordinator = BannerReloadCoordinator(adProvider: provider, adGate: gate)

        await #expect(throws: CancellationError.self) {
            _ = try await coordinator.reloadIfGateOpen(now: days(10, after: firstLaunch))
        }
        #expect(await provider.refreshCallCount == 1)
    }

    // MARK: Gap 2 — concurrent reloads never share a handle (#1058)

    // Bounded by `.timeLimit`: every wait inside `InterleavingAdProvider` is a
    // cancellable `ReadinessLatch.wait()`, so the limit's cancellation unblocks it.
    @Test(.timeLimit(.minutes(1)))
    func concurrentReloadsEachReturnTheirOwnHandle() async throws {
        let provider = InterleavingAdProvider(expectedLoads: 2)
        let (gate, _) = makeGate(AdGateState(firstLaunchAt: firstLaunch))
        let coordinator = BannerReloadCoordinator(adProvider: provider, adGate: gate)
        let now = days(10, after: firstLaunch)

        async let first = coordinator.reloadIfGateOpen(now: now)
        async let second = coordinator.reloadIfGateOpen(now: now)
        let statuses = try await [first, second]

        guard case let .loaded(firstHandle) = statuses[0],
              case let .loaded(secondHandle) = statuses[1] else {
            Issue.record("expected two .loaded statuses, got \(statuses)")
            return
        }
        #expect(
            firstHandle != secondHandle,
            "each reload must return the handle it loaded, not the provider's last-written status"
        )
    }
}

/// Two loads that are both in flight before either completes. `bannerStatus`
/// is last-writer-wins (like `LiveAdMobAdProvider`'s) and answers only once
/// every load has completed, so a caller that re-reads it after its own load
/// gets whichever load finished last instead of the handle it loaded.
private actor InterleavingAdProvider: AdProvider {
    private let expectedLoads: Int
    private let allInFlight = ReadinessLatch()
    private let allCompleted = ReadinessLatch()
    private var started = 0
    private var completed = 0
    private var lastLoaded: AdBannerHandle?

    init(expectedLoads: Int) {
        self.expectedLoads = expectedLoads
    }

    func initialize() async throws {}

    func awaitReady() async throws {}

    var bannerStatus: AdBannerStatus {
        get async {
            try? await allCompleted.wait()
            return lastLoaded.map { .loaded($0) } ?? .notInitialized
        }
    }

    func refreshBanner() async throws -> AdBannerHandle {
        let handle = AdBannerHandle()
        started += 1
        if started == expectedLoads { allInFlight.open() }
        try await allInFlight.wait()
        lastLoaded = handle
        completed += 1
        if completed == expectedLoads { allCompleted.open() }
        return handle
    }

    func dispose(handle: AdBannerHandle) async {}
}
