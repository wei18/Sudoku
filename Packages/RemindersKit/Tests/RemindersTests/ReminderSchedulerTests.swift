// Foundation tests driven by the fakes (swift-testing-baseline). They assert the
// protocol-level contract: schedule records kind + content + trigger, cancel
// removes a kind, identifier-scoped replacement (re-scheduling a kind replaces
// rather than accumulates — proposal §3.2), and the Noop impls are inert.

import Foundation
import Testing

import Reminders
import RemindersTesting

@Suite("ReminderScheduler — Fake-driven contract")
struct ReminderSchedulerTests {

    @Test("schedule records kind, content, and trigger")
    func scheduleRecordsCall() async {
        let scheduler = FakeReminderScheduler()
        let content = ReminderContent(title: "Today's puzzle is ready", body: "Your daily Sudoku is waiting.")

        await scheduler.schedule(kind: .dailyReady, content: content, on: .dailyAt(hour: 9, minute: 0))

        let calls = await scheduler.scheduleCalls
        #expect(calls.count == 1)
        #expect(calls.first?.kind == .dailyReady)
        #expect(calls.first?.content == content)
        #expect(calls.first?.schedule == .dailyAt(hour: 9, minute: 0))
    }

    @Test("rescheduling a kind replaces (identifier-scoped), never accumulates")
    func identifierScopedReplacement() async {
        let scheduler = FakeReminderScheduler()

        await scheduler.schedule(
            kind: .dailyReady,
            content: ReminderContent(title: "v1", body: "first"),
            on: .dailyAt(hour: 9, minute: 0)
        )
        await scheduler.schedule(
            kind: .dailyReady,
            content: ReminderContent(title: "v2", body: "second"),
            on: .dailyAt(hour: 8, minute: 30)
        )

        // Full history shows both calls...
        let calls = await scheduler.scheduleCalls
        #expect(calls.count == 2)

        // ...but the pending state has exactly one entry for the kind (last wins).
        let pending = await scheduler.pending
        #expect(pending.count == 1)
        #expect(pending[.dailyReady]?.content.title == "v2")
        #expect(pending[.dailyReady]?.schedule == .dailyAt(hour: 8, minute: 30))
    }

    @Test("distinct kinds coexist as separate pending reminders")
    func distinctKindsCoexist() async {
        let scheduler = FakeReminderScheduler()

        await scheduler.schedule(kind: .dailyReady, content: ReminderContent(title: "a", body: "a"), on: .dailyAt(hour: 9, minute: 0))
        await scheduler.schedule(kind: .comeback, content: ReminderContent(title: "b", body: "b"), on: .after(seconds: 86_400))

        let pending = await scheduler.pending
        #expect(pending.count == 2)
        #expect(pending[.dailyReady] != nil)
        #expect(pending[.comeback]?.schedule == .after(seconds: 86_400))
    }

    @Test("cancel records the kind")
    func cancelRecordsKind() async {
        let scheduler = FakeReminderScheduler()

        await scheduler.cancel(kind: .streakKeeper)

        let cancels = await scheduler.cancelCalls
        #expect(cancels == [.streakKeeper])
    }

    @Test("cancelAll is counted")
    func cancelAllCounted() async {
        let scheduler = FakeReminderScheduler()

        await scheduler.cancelAll()
        await scheduler.cancelAll()

        let count = await scheduler.cancelAllCount
        #expect(count == 2)
    }

    @Test("ReminderKind raw value doubles as the stable identifier")
    func kindRawValueIsIdentifier() {
        #expect(ReminderKind.dailyReady.rawValue == "dailyReady")
        #expect(ReminderKind.streakKeeper.rawValue == "streakKeeper")
        #expect(ReminderKind.comeback.rawValue == "comeback")
        #expect(ReminderKind.allCases.count == 3)
    }

    @Test("NoopReminderScheduler is inert")
    func noopSchedulerInert() async {
        let scheduler = NoopReminderScheduler()
        // No state to assert — exercising the no-ops proves they conform + don't trap.
        await scheduler.schedule(kind: .dailyReady, content: ReminderContent(title: "x", body: "x"), on: .dailyAt(hour: 9, minute: 0))
        await scheduler.cancel(kind: .dailyReady)
        await scheduler.cancelAll()
    }
}

@Suite("NotificationAuthorizing — Fake-driven contract")
struct NotificationAuthorizingTests {

    @Test("scriptable current status")
    func scriptableCurrentStatus() async {
        let auth = FakeNotificationAuthorizing(status: .denied)
        let status = await auth.currentStatus()
        #expect(status == .denied)
    }

    @Test("requestAuthorization records provisional flag and resolves scripted status")
    func requestRecordsAndResolves() async {
        let auth = FakeNotificationAuthorizing(status: .notDetermined)
        await auth.setResolvedStatus(.authorized)

        let resolved = await auth.requestAuthorization(provisional: false)
        #expect(resolved == .authorized)

        let flags = await auth.requestedProvisionalFlags
        #expect(flags == [false])

        // Current status now reflects the resolution.
        let current = await auth.currentStatus()
        #expect(current == .authorized)
    }

    @Test("provisional request is recorded as provisional")
    func provisionalRecorded() async {
        let auth = FakeNotificationAuthorizing()
        await auth.setResolvedStatus(.provisional)

        let resolved = await auth.requestAuthorization(provisional: true)
        #expect(resolved == .provisional)

        let flags = await auth.requestedProvisionalFlags
        #expect(flags == [true])
    }

    @Test("denied resolution is honored")
    func deniedResolution() async {
        let auth = FakeNotificationAuthorizing()
        await auth.setResolvedStatus(.denied)

        let resolved = await auth.requestAuthorization(provisional: false)
        #expect(resolved == .denied)
    }

    @Test("NoopNotificationAuthorizing reports notDetermined and never prompts")
    func noopAuthorizer() async {
        let auth = NoopNotificationAuthorizing()
        #expect(await auth.currentStatus() == .notDetermined)
        #expect(await auth.requestAuthorization(provisional: false) == .notDetermined)
    }
}
