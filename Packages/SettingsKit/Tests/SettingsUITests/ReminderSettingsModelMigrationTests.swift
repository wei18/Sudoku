// ReminderSettingsModelMigrationTests — the #817 seed-from-ground-truth
// migration, split from ReminderSettingsModelTests (that file sits at the
// SwiftLint file_length ceiling).
//
// Installs predating the persisted `isScheduled` flag have NO stored value.
// A blind `true` default would mis-render exactly the pre-#817 population who
// tapped "Turn off reminders": their notification was genuinely cancelled but
// nothing recorded it, so they would see "On" while reality is off. Instead,
// `onAppear()` seeds the flag ONCE from `scheduler.hasPending(kind:)` — the
// scheduler-side ground truth — and persists the result.

import Foundation
import Testing
@testable import SettingsUI
@testable import Reminders
import RemindersTesting

@MainActor
@Suite("ReminderSettingsModel — #817 isScheduled seed-from-ground-truth migration")
struct ReminderSettingsModelMigrationTests {

    /// Tri-state persisted-flag seam; `nil` = no value ever persisted.
    private final class ScheduledBox {
        var isScheduled: Bool?
        init(_ isScheduled: Bool?) { self.isScheduled = isScheduled }
    }

    private func makeModel(
        scheduler: FakeReminderScheduler,
        scheduledBox: ScheduledBox
    ) -> ReminderSettingsModel {
        ReminderSettingsModel(
            permissionModel: ReminderPermissionModel(
                authorizer: FakeNotificationAuthorizing(status: .authorized)
            ),
            scheduler: scheduler,
            kind: .dailyReady,
            content: ReminderContent(title: "t", body: "b"),
            getFireTime: { (hour: 9, minute: 0) },
            setFireTime: { _ in },
            getIsScheduled: { scheduledBox.isScheduled },
            setIsScheduled: { scheduledBox.isScheduled = $0 }
        )
    }

    @Test("missing key + no pending request → onAppear seeds AND persists false (pre-fix disable() population)")
    func missingKeyNoPendingSeedsFalse() async {
        let scheduler = FakeReminderScheduler() // nothing pending
        let box = ScheduledBox(nil) // install predates the flag
        let model = makeModel(scheduler: scheduler, scheduledBox: box)
        #expect(model.isScheduled == true) // pre-seed first-frame default

        await model.onAppear()

        #expect(model.isScheduled == false) // ground truth: nothing pending
        #expect(box.isScheduled == false) // persisted, so the seed runs once
    }

    @Test("missing key + pending request exists → onAppear seeds AND persists true")
    func missingKeyWithPendingSeedsTrue() async {
        let scheduler = FakeReminderScheduler()
        await scheduler.seedPending(kind: .dailyReady) // scheduled last session
        let box = ScheduledBox(nil)
        let model = makeModel(scheduler: scheduler, scheduledBox: box)

        await model.onAppear()

        #expect(model.isScheduled == true)
        #expect(box.isScheduled == true)
    }

    @Test("persisted value present → onAppear does NOT re-seed from the scheduler")
    func persistedValueWinsOverGroundTruth() async {
        let scheduler = FakeReminderScheduler()
        await scheduler.seedPending(kind: .dailyReady) // ground truth says pending…
        let box = ScheduledBox(false) // …but the user explicitly turned it off
        let model = makeModel(scheduler: scheduler, scheduledBox: box)

        await model.onAppear()

        #expect(model.isScheduled == false) // persisted intent wins
        #expect(box.isScheduled == false)
    }
}
