import Foundation
import Synchronization
import MonetizationCore
import MonetizationTesting
@testable import MonetizationUI

// Shared fixtures for the `BannerSessionModel` suites (#1058). Every wait in
// those suites is bounded: a regression must fail a test, never hang it.

enum SessionFixture {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-01-01T00:00:00Z.
    static let firstLaunch = Date(timeIntervalSince1970: 1_767_225_600)

    /// Ten days after first launch.
    static let today = firstLaunch.addingTimeInterval(10 * 86_400)

    static let openState = AdGateState(firstLaunchAt: firstLaunch)

    static let dismissedTodayState = AdGateState(
        firstLaunchAt: firstLaunch,
        dismissedDate: calendar.startOfDay(for: today)
    )

    static func gate(_ state: AdGateState) -> (AdGate, FakeAdGateStateStore) {
        let store = FakeAdGateStateStore(initial: state)
        return (AdGate(store: store, calendar: calendar), store)
    }
}

/// Injected wall clock for day-rollover tests.
final class TestClock: Sendable {
    private let current: Mutex<Date>

    init(_ start: Date) {
        current = Mutex(start)
    }

    var now: Date { current.withLock { $0 } }

    func advance(days: Double) {
        current.withLock { $0 = $0.addingTimeInterval(days * 86_400) }
    }
}

actor CallCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}

actor EventLog {
    private(set) var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }
}

/// Set from a `withObservationTracking` `onChange` handler.
final class ChangeFlag: Sendable {
    private let flag = Mutex(false)

    var isSet: Bool { flag.withLock { $0 } }

    func set() {
        flag.withLock { $0 = true }
    }
}

/// Records the moment a load reaches the provider; readiness is held on a
/// latch the test opens.
actor OrderRecordingAdProvider: AdProvider {
    let log: EventLog
    let readiness: ReadinessLatch

    init(log: EventLog, readiness: ReadinessLatch) {
        self.log = log
        self.readiness = readiness
    }

    func initialize() async throws {}

    func awaitReady() async throws {
        try await readiness.wait()
    }

    var bannerStatus: AdBannerStatus { .notInitialized }

    func refreshBanner() async throws -> AdBannerHandle {
        await log.record("adLoadStarted")
        return AdBannerHandle()
    }

    func dispose(handle: AdBannerHandle) async {}
}

/// Polls `condition` every 10ms until it holds or `timeout` elapses.
@MainActor
func eventually(timeout: Duration = .seconds(2), _ condition: () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !(await condition()) {
        if ContinuousClock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

extension AdBannerStatus {
    var loadedHandle: AdBannerHandle? {
        if case let .loaded(handle) = self { return handle }
        return nil
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
