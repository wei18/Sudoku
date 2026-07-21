// ReminderSettingsModelForegroundRefreshTests — split from
// ReminderSettingsModelTests (that file sits at the SwiftLint file_length
// ceiling), mirroring the ReminderSettingsModelMigrationTests split.
//
// Navigation-audit finding: `ReminderPermissionModel.openSettings()` backgrounds
// the app into Settings.app via `UIApplication.shared.open(...)` WITHOUT this
// Settings screen ever leaving the view hierarchy, so the section's
// `.task { await model.onAppear() }` never re-fires on return (SwiftUI only
// re-fires `.task` on identity change, not on foreground — same family as #761).
// `ReminderSettingsSection` now also re-calls `model.onAppear()` from a
// `@Environment(\.scenePhase) == .active` `.onChange` hook. These tests drive
// the same call the hook drives — the section's `.onChange` itself needs no
// separate coverage since it is a one-line forward to `onAppear()`.

import Foundation
import Testing
@testable import SettingsUI
@testable import Reminders
import RemindersTesting

@MainActor
@Suite("ReminderSettingsModel — foreground re-poll (scenePhase hook)")
struct ReminderSettingsModelForegroundRefreshTests {

    /// Tri-state persisted-flag seam; `nil` = no value ever persisted.
    private final class ScheduledBox {
        var isScheduled: Bool?
        init(_ isScheduled: Bool? = true) { self.isScheduled = isScheduled }
    }

    private func makeModel(
        scheduler: FakeReminderScheduler,
        authorizer: FakeNotificationAuthorizing,
        scheduledBox: ScheduledBox = ScheduledBox()
    ) -> ReminderSettingsModel {
        ReminderSettingsModel(
            permissionModel: ReminderPermissionModel(authorizer: authorizer),
            scheduler: scheduler,
            kind: .dailyReady,
            content: ReminderContent(title: "t", body: "b"),
            getFireTime: { (hour: 9, minute: 0) },
            setFireTime: { _ in },
            getIsScheduled: { scheduledBox.isScheduled },
            setIsScheduled: { scheduledBox.isScheduled = $0 }
        )
    }

    /// Pins the fix itself: denied → user flips Allow on in Settings.app →
    /// foreground return re-polls and picks it up.
    @Test("onAppear() called again (simulating a foreground return from Settings.app) re-reads the status change")
    func onAppearAgainReadsForegroundStatusChange() async {
        let authorizer = FakeNotificationAuthorizing(status: .denied)
        let model = makeModel(scheduler: FakeReminderScheduler(), authorizer: authorizer)

        await model.onAppear() // initial Settings-screen mount
        #expect(model.status == .denied)
        #expect(model.isEnabled == false)

        // User leaves to Settings.app, flips Allow on, returns to the
        // foreground — the scenePhase hook re-calls onAppear() exactly like this.
        await authorizer.setCurrentStatus(.authorized)
        await model.onAppear()

        #expect(model.status == .authorized)
        #expect(model.isEnabled == true)
    }

    /// The scenePhase foreground hook means `onAppear()` can now run many times
    /// per screen visit (once per app switch), not just once at mount. Pins
    /// that repeat calls stay safe for the #817 one-shot migration: once
    /// `isScheduled` has been seeded from scheduler ground truth, a later call
    /// must not re-derive or clobber it — the migration's `getIsScheduled() ==
    /// nil` guard makes every call after the first a no-op past that check.
    @Test("onAppear() repeat calls do not re-run the #817 one-shot migration")
    func onAppearRepeatDoesNotReRunMigration() async {
        let scheduler = FakeReminderScheduler()
        await scheduler.seedPending(kind: .dailyReady) // ground truth: a pending request exists
        let scheduledBox = ScheduledBox(nil) // no persisted value yet (pre-#817 install)
        let model = makeModel(
            scheduler: scheduler,
            authorizer: FakeNotificationAuthorizing(status: .authorized),
            scheduledBox: scheduledBox
        )

        await model.onAppear() // first call: seeds isScheduled=true from ground truth, persists it
        #expect(model.isScheduled == true)
        #expect(scheduledBox.isScheduled == true)

        // Simulate the user turning reminders off in-app, THEN a foreground
        // re-poll (e.g. they briefly switched to Settings.app for something
        // unrelated and came back). The migration must not re-fire and flip
        // isScheduled back to the ground-truth `true`, clobbering the explicit
        // off the user just persisted.
        await model.disable()
        #expect(scheduledBox.isScheduled == false)

        await model.onAppear() // simulated foreground re-poll (the scenePhase hook)

        #expect(model.isScheduled == false) // untouched — migration guard held
        #expect(scheduledBox.isScheduled == false)
    }
}
