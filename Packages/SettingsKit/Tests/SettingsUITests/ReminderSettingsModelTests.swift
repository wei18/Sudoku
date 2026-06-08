// ReminderSettingsModelTests — drives the #287 shared Settings reminder entry
// model with the RemindersTesting fakes + an in-memory fire-time seam (no system
// center, no UserDefaults touched).
//
// Pins the Settings-initiated enable flow: enabling presents the primer, accept
// fires exactly one system prompt and (on grant) schedules the daily reminder at
// the persisted time; the picker persists + reschedules only when granted; and
// onAppear re-reads a Settings-app status change.

import Foundation
import Testing
import UserNotifications
@testable import SettingsUI
@testable import Reminders
import RemindersTesting

@MainActor
@Suite("GameShellUI — ReminderSettingsModel (#287 Settings entry)")
struct ReminderSettingsModelTests {

    /// `UTC` so `dateComponents([.hour,.minute], from:)` round-trips regardless
    /// of the test machine's timezone.
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

    /// In-memory fire-time seam (replaces the per-app UserDefaults store in tests).
    private final class TimeBox {
        var time: (hour: Int, minute: Int)
        init(_ time: (hour: Int, minute: Int)) { self.time = time }
    }

    /// `Sendable` event recorder — the model's `emit` is `@Sendable`, so it can't
    /// capture a mutable local. An actor gives data-race-free recording.
    private actor EventRecorder {
        private(set) var events: [ReminderSettingsModel.Event] = []
        func record(_ event: ReminderSettingsModel.Event) { events.append(event) }
    }

    private func makeModel(
        scheduler: FakeReminderScheduler,
        authorizer: FakeNotificationAuthorizing,
        box: TimeBox,
        emit: @escaping @Sendable (ReminderSettingsModel.Event) -> Void = { _ in }
    ) -> ReminderSettingsModel {
        ReminderSettingsModel(
            permissionModel: ReminderPermissionModel(authorizer: authorizer),
            scheduler: scheduler,
            kind: .dailyReady,
            content: ReminderContent(title: "t", body: "b"),
            getFireTime: { box.time },
            setFireTime: { box.time = $0 },
            emit: emit,
            calendar: utc
        )
    }

    // MARK: - Seeding

    @Test("seeds the picker from the persisted fire time")
    func seedsFromPersisted() {
        let box = TimeBox((hour: 7, minute: 30))
        let model = makeModel(
            scheduler: FakeReminderScheduler(),
            authorizer: FakeNotificationAuthorizing(status: .authorized),
            box: box
        )
        let components = utc.dateComponents([.hour, .minute], from: model.fireDate)
        #expect(components.hour == 7)
        #expect(components.minute == 30)
    }

    // MARK: - onAppear

    @Test("onAppear refreshes status from the authorizer")
    func onAppearRefreshesStatus() async {
        let authorizer = FakeNotificationAuthorizing(status: .denied)
        let model = makeModel(
            scheduler: FakeReminderScheduler(),
            authorizer: authorizer,
            box: TimeBox((hour: 9, minute: 0))
        )
        #expect(model.status == .notDetermined) // seeded
        await model.onAppear()
        #expect(model.status == .denied)
        #expect(model.isEnabled == false)
    }

    // MARK: - Enable / primer flow

    @Test("enable() presents the primer; no system prompt fires yet")
    func enablePresentsPrimer() async {
        let authorizer = FakeNotificationAuthorizing(status: .notDetermined)
        let model = makeModel(
            scheduler: FakeReminderScheduler(),
            authorizer: authorizer,
            box: TimeBox((hour: 9, minute: 0))
        )
        model.enable()
        #expect(model.isPrimerPresented == true)
        let flags = await authorizer.requestedProvisionalFlags
        #expect(flags.isEmpty) // soft pre-ask only — no system prompt yet
    }

    @Test("acceptPrimer (granted) fires one prompt + schedules the daily at persisted time")
    func acceptGrantedSchedules() async throws {
        let scheduler = FakeReminderScheduler()
        let authorizer = FakeNotificationAuthorizing(status: .notDetermined)
        await authorizer.setResolvedStatus(.authorized)
        let recorder = EventRecorder()
        let model = makeModel(
            scheduler: scheduler,
            authorizer: authorizer,
            box: TimeBox((hour: 8, minute: 15)),
            emit: { event in Task { await recorder.record(event) } }
        )

        model.enable()
        await model.acceptPrimer()

        #expect(model.status == .authorized)
        #expect(model.isEnabled == true)
        #expect(model.isPrimerPresented == false)

        // exactly one system prompt, explicit (not provisional)
        let flags = await authorizer.requestedProvisionalFlags
        #expect(flags == [false])

        // scheduled at the persisted time, identifier-scoped to the kind
        let pending = await scheduler.pending
        #expect(pending.count == 1)
        #expect(pending[.dailyReady]?.schedule == .dailyAt(hour: 8, minute: 15))

        // the recorded schedule maps to a repeating calendar trigger (live seam)
        let resolved = try #require(pending[.dailyReady])
        let trigger = LiveReminderScheduler.trigger(for: resolved.schedule)
        let calendarTrigger = try #require(trigger as? UNCalendarNotificationTrigger)
        #expect(calendarTrigger.repeats == true)
        #expect(calendarTrigger.dateComponents.hour == 8)
        #expect(calendarTrigger.dateComponents.minute == 15)

        let events = try await settledEvents(recorder, containing: .scheduled(kind: "dailyReady"))
        #expect(events.contains(.primerAccepted(kind: "dailyReady")))
        #expect(events.contains(.scheduled(kind: "dailyReady")))
    }

    @Test("acceptPrimer (denied) fires the prompt but schedules nothing")
    func acceptDeniedDoesNotSchedule() async {
        let scheduler = FakeReminderScheduler()
        let authorizer = FakeNotificationAuthorizing(status: .notDetermined)
        await authorizer.setResolvedStatus(.denied)
        let model = makeModel(scheduler: scheduler, authorizer: authorizer, box: TimeBox((hour: 9, minute: 0)))

        model.enable()
        await model.acceptPrimer()

        #expect(model.status == .denied)
        #expect(model.isPrimerPresented == false)
        let calls = await scheduler.scheduleCalls
        #expect(calls.isEmpty)
    }

    @Test("declinePrimer dismisses + fires no system prompt (repeatable)")
    func declinePrimerNoPrompt() async throws {
        let authorizer = FakeNotificationAuthorizing(status: .notDetermined)
        let recorder = EventRecorder()
        let model = makeModel(
            scheduler: FakeReminderScheduler(),
            authorizer: authorizer,
            box: TimeBox((hour: 9, minute: 0)),
            emit: { event in Task { await recorder.record(event) } }
        )

        model.enable()
        model.declinePrimer()

        #expect(model.isPrimerPresented == false)
        let flags = await authorizer.requestedProvisionalFlags
        #expect(flags.isEmpty)
        let events = try await settledEvents(recorder, containing: .primerDeclined(kind: "dailyReady"))
        #expect(events == [.primerDeclined(kind: "dailyReady")])
    }

    // MARK: - Time picker

    @Test("changing the picker persists + reschedules when granted")
    func pickerPersistsAndReschedules() async throws {
        let scheduler = FakeReminderScheduler()
        let box = TimeBox((hour: 9, minute: 0))
        let model = makeModel(
            scheduler: scheduler,
            authorizer: FakeNotificationAuthorizing(status: .authorized),
            box: box
        )
        await model.onAppear() // -> .authorized so reschedule is permitted

        model.fireDate = date(hour: 21, minute: 15)

        #expect(box.time == (hour: 21, minute: 15)) // persisted

        let scheduled = try await firstScheduled(scheduler)
        #expect(scheduled.kind == .dailyReady)
        #expect(scheduled.schedule == .dailyAt(hour: 21, minute: 15))
    }

    @Test("changing the picker persists but does NOT reschedule when not granted")
    func pickerPersistsNoScheduleWhenDenied() async {
        let scheduler = FakeReminderScheduler()
        let box = TimeBox((hour: 9, minute: 0))
        let model = makeModel(
            scheduler: scheduler,
            authorizer: FakeNotificationAuthorizing(status: .denied),
            box: box
        )
        await model.onAppear() // -> .denied

        model.fireDate = date(hour: 6, minute: 45)
        #expect(box.time == (hour: 6, minute: 45)) // persisted regardless

        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))
        let calls = await scheduler.scheduleCalls
        #expect(calls.isEmpty)
    }

    // MARK: - Disable

    /// The Settings section's OFF affordance (#287 CR): once reminders are On
    /// (authorized + enabled), the `disableRow` button calls `model.disable()`,
    /// which must cancel the scheduled reminder AND emit `.cancelled` so the
    /// on→off funnel is observable. This pins the affordance's contract from the
    /// On state the row is shown in.
    @Test("OFF affordance (authorized → disable) cancels + emits .cancelled")
    func offAffordanceCancelsAndEmitsWhenOn() async throws {
        let scheduler = FakeReminderScheduler()
        let recorder = EventRecorder()
        let model = makeModel(
            scheduler: scheduler,
            authorizer: FakeNotificationAuthorizing(status: .authorized),
            box: TimeBox((hour: 9, minute: 0)),
            emit: { event in Task { await recorder.record(event) } }
        )
        await model.onAppear() // -> .authorized: the row's On state where disableRow shows
        #expect(model.isEnabled == true)

        // What the disableRow Button action does:
        await model.disable()

        let cancels = await scheduler.cancelCalls
        #expect(cancels == [.dailyReady])
        let events = try await settledEvents(recorder, containing: .cancelled(kind: "dailyReady"))
        #expect(events.contains(.cancelled(kind: "dailyReady")))
    }

    @Test("enable() is a no-op while the primer is already presented (double-tap guard)")
    func enableDoubleTapGuarded() {
        let model = makeModel(
            scheduler: FakeReminderScheduler(),
            authorizer: FakeNotificationAuthorizing(status: .notDetermined),
            box: TimeBox((hour: 9, minute: 0))
        )
        model.enable()
        #expect(model.isPrimerPresented == true)
        // A second tap before the sheet commits must not re-enter.
        model.enable()
        #expect(model.isPrimerPresented == true)
    }

    @Test("disable() cancels the pending request for the kind")
    func disableCancels() async throws {
        let scheduler = FakeReminderScheduler()
        let recorder = EventRecorder()
        let model = makeModel(
            scheduler: scheduler,
            authorizer: FakeNotificationAuthorizing(status: .authorized),
            box: TimeBox((hour: 9, minute: 0)),
            emit: { event in Task { await recorder.record(event) } }
        )

        await model.disable()

        let cancels = await scheduler.cancelCalls
        #expect(cancels == [.dailyReady])
        let events = try await settledEvents(recorder, containing: .cancelled(kind: "dailyReady"))
        #expect(events == [.cancelled(kind: "dailyReady")])
    }

    // MARK: - Denied recovery

    @Test("showDeniedExplainer toggles the explainer sheet")
    func showDeniedExplainer() {
        let model = makeModel(
            scheduler: FakeReminderScheduler(),
            authorizer: FakeNotificationAuthorizing(status: .denied),
            box: TimeBox((hour: 9, minute: 0))
        )
        model.showDeniedExplainer()
        #expect(model.isDeniedExplainerPresented == true)
        model.dismissDeniedExplainer()
        #expect(model.isDeniedExplainerPresented == false)
    }

    // MARK: - Helpers

    private func firstScheduled(_ scheduler: FakeReminderScheduler) async throws -> ScheduledReminder {
        for _ in 0..<100 {
            let calls = await scheduler.scheduleCalls
            if let first = calls.first { return first }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw PollTimeout()
    }

    /// Poll the recorder until it contains `event` (emit dispatches via a
    /// detached `Task` so the bridge is async), then return the recorded list.
    private func settledEvents(
        _ recorder: EventRecorder,
        containing event: ReminderSettingsModel.Event
    ) async throws -> [ReminderSettingsModel.Event] {
        for _ in 0..<100 {
            let events = await recorder.events
            if events.contains(event) { return events }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw PollTimeout()
    }

    private struct PollTimeout: Error {}
}
