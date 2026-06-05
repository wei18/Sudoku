// ReminderTimeSettingsModelTests — the #321 Settings fire-time picker.
//
// Drives `ReminderTimeSettingsModel` with RemindersTesting fakes and an
// ephemeral `UserDefaults` suite, pinning the persist → reschedule wiring:
// changing the picker (1) persists the new hour/minute to the store and
// (2) reschedules `.dailyAt(hour,minute)` — but only when notifications are
// granted. The resulting schedule is fed through the #319 `trigger(for:)` seam
// to assert the live `UNCalendarNotificationTrigger` carries the picked time.

import Foundation
import Testing
import UserNotifications
@testable import Reminders
import RemindersTesting
import Telemetry
@testable import SudokuUI

@MainActor
@Suite("ReminderTimeSettingsModel — #321 Settings fire-time picker")
struct ReminderTimeSettingsModelTests {

    private func ephemeralStore() -> ReminderSettingsStore {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        return ReminderSettingsStore(defaults: defaults)
    }

    /// `UTC` so `dateComponents([.hour,.minute], from:)` round-trips the exact
    /// picked hour/minute regardless of the test machine's timezone.
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(hour: Int, minute: Int) -> Date {
        var components = utc.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return utc.date(from: components)!
    }

    private func makeModel(
        store: ReminderSettingsStore,
        scheduler: FakeReminderScheduler,
        authorizer: FakeNotificationAuthorizing
    ) -> ReminderTimeSettingsModel {
        ReminderTimeSettingsModel(
            settingsStore: store,
            scheduler: scheduler,
            authorizer: authorizer,
            content: ReminderContent(title: "t", body: "b"),
            emit: { _ in },
            calendar: utc
        )
    }

    @Test("seeds the picker from the persisted fire time")
    func seedsFromPersisted() {
        let store = ephemeralStore()
        store.dailyReadyFireTime = ReminderFireTime(hour: 7, minute: 30)
        let model = makeModel(
            store: store,
            scheduler: FakeReminderScheduler(),
            authorizer: FakeNotificationAuthorizing(status: .authorized)
        )

        let components = utc.dateComponents([.hour, .minute], from: model.fireDate)
        #expect(components.hour == 7)
        #expect(components.minute == 30)
    }

    @Test("changing the picker persists the new time AND reschedules (authorized)")
    func changePersistsAndReschedules() async throws {
        let store = ephemeralStore()
        let scheduler = FakeReminderScheduler()
        let model = makeModel(
            store: store,
            scheduler: scheduler,
            authorizer: FakeNotificationAuthorizing(status: .authorized)
        )

        model.fireDate = date(hour: 21, minute: 15)

        // (1) persisted
        #expect(store.dailyReadyFireTime == ReminderFireTime(hour: 21, minute: 15))

        // (2) rescheduled — the didSet spawns a Task; await the scheduler's
        // recorded call (poll until the async reschedule lands).
        let scheduled = try? await firstScheduled(scheduler)
        #expect(scheduled?.kind == .dailyReady)
        #expect(scheduled?.schedule == .dailyAt(hour: 21, minute: 15))

        // #319 seam: the recorded schedule maps to a repeating calendar trigger
        // carrying the picked hour/minute.
        let resolved = try #require(scheduled)
        let trigger = LiveReminderScheduler.trigger(for: resolved.schedule)
        let calendar = try #require(trigger as? UNCalendarNotificationTrigger)
        #expect(calendar.repeats == true)
        #expect(calendar.dateComponents.hour == 21)
        #expect(calendar.dateComponents.minute == 15)
    }

    @Test("permission not granted: persists but does NOT schedule")
    func notGrantedDoesNotSchedule() async {
        let store = ephemeralStore()
        let scheduler = FakeReminderScheduler()
        let model = makeModel(
            store: store,
            scheduler: scheduler,
            authorizer: FakeNotificationAuthorizing(status: .denied)
        )

        model.fireDate = date(hour: 6, minute: 45)

        // Persisted regardless of permission — ready for a later grant.
        #expect(store.dailyReadyFireTime == ReminderFireTime(hour: 6, minute: 45))

        // Give the spawned reschedule Task a chance to run, then assert nothing
        // was scheduled (a denied user has no pending request to replace).
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))
        let calls = await scheduler.scheduleCalls
        #expect(calls.isEmpty)
    }

    @Test("re-picking replaces, never duplicates (identifier-scoped)")
    func repickReplaces() async {
        let store = ephemeralStore()
        let scheduler = FakeReminderScheduler()
        let model = makeModel(
            store: store,
            scheduler: scheduler,
            authorizer: FakeNotificationAuthorizing(status: .authorized)
        )

        model.fireDate = date(hour: 8, minute: 0)
        _ = try? await firstScheduled(scheduler)
        model.fireDate = date(hour: 20, minute: 0)
        // Poll until the second reschedule (8pm) lands — the two didSet-spawned
        // Tasks aren't ordered, so wait for the latest pick rather than a fixed sleep.
        try? await scheduleSettles(scheduler, to: .dailyAt(hour: 20, minute: 0))

        let pending = await scheduler.pending
        // Identifier-scoped: exactly one pending request for the kind, at the
        // latest picked time (replace-in-place, never accumulate — §3.2).
        #expect(pending.count == 1)
        #expect(pending[.dailyReady]?.schedule == .dailyAt(hour: 20, minute: 0))
    }

    /// Poll the fake scheduler until the async (didSet-spawned) reschedule lands.
    private func firstScheduled(_ scheduler: FakeReminderScheduler) async throws -> ScheduledReminder {
        for _ in 0..<100 {
            let calls = await scheduler.scheduleCalls
            if let first = calls.first { return first }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw PollTimeout()
    }

    /// Poll until the kind's pending schedule equals `expected` (the two
    /// didSet-spawned Tasks are unordered, so wait for the latest pick to settle).
    private func scheduleSettles(
        _ scheduler: FakeReminderScheduler,
        to expected: ReminderSchedule
    ) async throws {
        for _ in 0..<100 {
            let pending = await scheduler.pending
            if pending[.dailyReady]?.schedule == expected { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw PollTimeout()
    }

    private struct PollTimeout: Error {}
}
