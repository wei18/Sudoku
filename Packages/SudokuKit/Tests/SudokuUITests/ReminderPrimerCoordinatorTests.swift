// ReminderPrimerCoordinatorTests — the Sudoku U1 daily-ready primer flow
// (#287 Phase 2 chunk 2). Drives the coordinator with RemindersTesting fakes +
// a recording telemetry emit closure, asserting the value-moment → accept →
// schedule path (flow S02→S05) and the decline / denied branches.

import Foundation
// refactor/settingskit-target: `ReminderPermissionModel` + the primer/denied
// copy types moved out of GameShellUI into SettingsUI.
import SettingsUI
import Reminders
import RemindersTesting
import SwiftUI
import Telemetry
import Testing
@testable import SudokuUI

@MainActor
@Suite("ReminderPrimerCoordinator — daily-ready flow")
struct ReminderPrimerCoordinatorTests {

    // Thread-safe recorder for the (Sendable) emit closure.
    private final class EventRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [TelemetryEvent] = []
        func record(_ event: TelemetryEvent) {
            lock.lock(); defer { lock.unlock() }
            storage.append(event)
        }
        var events: [TelemetryEvent] {
            lock.lock(); defer { lock.unlock() }
            return storage
        }
    }

    private func makeCoordinator(
        authorizer: FakeNotificationAuthorizing,
        scheduler: FakeReminderScheduler,
        store: ReminderSettingsStore,
        recorder: EventRecorder
    ) -> ReminderPrimerCoordinator {
        ReminderPrimerCoordinator(
            permissionModel: ReminderPermissionModel(authorizer: authorizer),
            scheduler: scheduler,
            getFireTime: {
                let time = store.dailyReadyFireTime
                return (hour: time.hour, minute: time.minute)
            },
            content: ReminderContent(title: "t", body: "b"),
            primerCopy: ReminderPrimerCopy(
                title: "", lede: "", bullets: [], acceptCTA: "", declineCTA: "", fineprint: ""
            ),
            deniedCopy: ReminderDeniedCopy(
                title: "", message: "", openSettingsCTA: "", dismissCTA: "", macOSGuidance: ""
            ),
            emit: { recorder.record($0) }
        )
    }

    private func ephemeralStore() -> ReminderSettingsStore {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        return ReminderSettingsStore(defaults: defaults)
    }

    @Test("presentPrimer emits shown + opens the sheet")
    func presentPrimerEmitsShown() async {
        let recorder = EventRecorder()
        let coordinator = makeCoordinator(
            authorizer: FakeNotificationAuthorizing(status: .notDetermined),
            scheduler: FakeReminderScheduler(),
            store: ephemeralStore(),
            recorder: recorder
        )

        await coordinator.presentPrimer()

        #expect(coordinator.isPrimerPresented)
        #expect(recorder.events == [.reminderPrimerShown(kind: "dailyReady")])
    }

    @Test("accept → authorized schedules the daily reminder at the default 9 AM")
    func acceptAuthorizedSchedules() async {
        let recorder = EventRecorder()
        let authorizer = FakeNotificationAuthorizing(status: .notDetermined)
        await authorizer.setResolvedStatus(.authorized)
        let scheduler = FakeReminderScheduler()
        let coordinator = makeCoordinator(
            authorizer: authorizer,
            scheduler: scheduler,
            store: ephemeralStore(),
            recorder: recorder
        )

        await coordinator.acceptPrimer()

        #expect(!coordinator.isPrimerPresented)
        let pending = await scheduler.pending
        let scheduled = try? #require(pending[.dailyReady])
        #expect(scheduled?.kind == .dailyReady)
        #expect(scheduled?.schedule == .dailyAt(hour: 9, minute: 0))
        #expect(recorder.events.contains(.reminderPrimerAccepted(kind: "dailyReady")))
        #expect(recorder.events.contains(.reminderScheduled(kind: "dailyReady")))
    }

    @Test("accept → denied does NOT schedule")
    func acceptDeniedDoesNotSchedule() async {
        let recorder = EventRecorder()
        let authorizer = FakeNotificationAuthorizing(status: .notDetermined)
        await authorizer.setResolvedStatus(.denied)
        let scheduler = FakeReminderScheduler()
        let coordinator = makeCoordinator(
            authorizer: authorizer,
            scheduler: scheduler,
            store: ephemeralStore(),
            recorder: recorder
        )

        await coordinator.acceptPrimer()

        let calls = await scheduler.scheduleCalls
        #expect(calls.isEmpty)
        #expect(recorder.events.contains(.reminderPrimerAccepted(kind: "dailyReady")))
        #expect(!recorder.events.contains(.reminderScheduled(kind: "dailyReady")))
    }

    @Test("decline emits declined, fires no system prompt, schedules nothing")
    func declineSchedulesNothing() async {
        let recorder = EventRecorder()
        let authorizer = FakeNotificationAuthorizing(status: .notDetermined)
        let scheduler = FakeReminderScheduler()
        let coordinator = makeCoordinator(
            authorizer: authorizer,
            scheduler: scheduler,
            store: ephemeralStore(),
            recorder: recorder
        )

        coordinator.declinePrimer()

        #expect(!coordinator.isPrimerPresented)
        let requested = await authorizer.requestedProvisionalFlags
        #expect(requested.isEmpty)
        let calls = await scheduler.scheduleCalls
        #expect(calls.isEmpty)
        #expect(recorder.events == [.reminderPrimerDeclined(kind: "dailyReady")])
    }

    @Test("scheduleDailyReady honors a persisted non-default fire time (#321 seam)")
    func scheduleUsesPersistedTime() async {
        let recorder = EventRecorder()
        let store = ephemeralStore()
        store.dailyReadyFireTime = ReminderFireTime(hour: 7, minute: 30)
        let scheduler = FakeReminderScheduler()
        let coordinator = makeCoordinator(
            authorizer: FakeNotificationAuthorizing(status: .authorized),
            scheduler: scheduler,
            store: store,
            recorder: recorder
        )

        await coordinator.scheduleDailyReady()

        let pending = await scheduler.pending
        #expect(pending[.dailyReady]?.schedule == .dailyAt(hour: 7, minute: 30))
    }

    @Test("re-accepting replaces, never duplicates (identifier-scoped)")
    func rescheduleReplaces() async {
        let recorder = EventRecorder()
        let authorizer = FakeNotificationAuthorizing(status: .notDetermined)
        await authorizer.setResolvedStatus(.authorized)
        let scheduler = FakeReminderScheduler()
        let coordinator = makeCoordinator(
            authorizer: authorizer,
            scheduler: scheduler,
            store: ephemeralStore(),
            recorder: recorder
        )

        await coordinator.acceptPrimer()
        await coordinator.acceptPrimer()

        let pending = await scheduler.pending
        #expect(pending.count == 1)
        #expect(pending[.dailyReady] != nil)
    }
}

@Suite("ReminderSettingsStore — persisted fire time (#321 seam)")
struct ReminderSettingsStoreTests {

    private func ephemeral() -> (ReminderSettingsStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        return (ReminderSettingsStore(defaults: defaults), defaults)
    }

    @Test("defaults to 9:00 AM when unset")
    func defaultsTo9AM() {
        let (store, _) = ephemeral()
        #expect(store.dailyReadyFireTime == ReminderFireTime(hour: 9, minute: 0))
    }

    @Test("round-trips a written fire time")
    func roundTrips() {
        let (store, _) = ephemeral()
        store.dailyReadyFireTime = ReminderFireTime(hour: 18, minute: 45)
        #expect(store.dailyReadyFireTime == ReminderFireTime(hour: 18, minute: 45))
    }

    @Test("a written midnight (0:00) is distinguishable from unset")
    func midnightIsNotDefault() {
        let (store, _) = ephemeral()
        store.dailyReadyFireTime = ReminderFireTime(hour: 0, minute: 0)
        // Without key-presence gating, integer(forKey:) → 0 would alias unset;
        // here it must read back as a real midnight, not the 9 AM default.
        #expect(store.dailyReadyFireTime == ReminderFireTime(hour: 0, minute: 0))
    }
}
