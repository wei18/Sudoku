// ReminderSettingsSectionTests — #880 (F-11 from #874's sweep report).
//
// `enableRow` (`.notDetermined`) toggles reminders in-app instantly; `deniedRow`
// (`.denied`) opens the recovery explainer whose primary action deep-links out
// to Settings.app. Prior to #880 the two rows were visually near-identical
// (same tint/layout, icon-only difference) despite that very different tap
// consequence. `deniedRow` now carries a trailing `arrow.up.forward.square`
// glyph — the standard iOS "leaves the app" affordance — plus a VoiceOver hint
// reusing the existing `deniedCopy.openSettingsCTA` string.
//
// No pre-existing snapshot baseline covered `ReminderSettingsSection` at all —
// the `SettingsView-fullpage-*` fixtures in `SettingsViewTests.swift` never
// wire a `reminderSettings` entry. This suite is the first visual coverage of
// the section, following the isolated-`Section` pattern established by
// `AudioSettingsSectionTests` (#879 / F-10, the sibling finding from the same
// #874 sweep).

import Foundation
import SnapshotTesting
import SwiftUI
import Testing

import Reminders
import RemindersTesting
@testable import SudokuUI
import SettingsUI

@MainActor
@Suite("ReminderSettingsSection — enable vs. denied row treatment (#880)")
struct ReminderSettingsSectionTests {

    private let sectionCopy = ReminderSettingsCopy(
        sectionTitle: "Reminders",
        enableTitle: "Daily reminder",
        enableCTA: "Turn On",
        enabledTitle: "Daily reminder",
        enabledStatus: "On",
        disableTitle: "Turn off reminders",
        timeTitle: "Time",
        deniedTitle: "Notifications are off",
        deniedCTA: "Fix"
    )
    private let primerCopy = ReminderPrimerCopy(
        title: "t", lede: "l", bullets: ["b"],
        acceptCTA: "a", declineCTA: "d", fineprint: "f"
    )
    private let deniedCopy = ReminderDeniedCopy(
        title: "t", message: "m", openSettingsCTA: "Open Settings",
        dismissCTA: "d", macOSGuidance: "g"
    )

    private func makeModel(status: ReminderAuthStatus) async -> ReminderSettingsModel {
        let authorizer = FakeNotificationAuthorizing(status: status)
        let model = ReminderSettingsModel(
            permissionModel: ReminderPermissionModel(authorizer: authorizer),
            scheduler: NoopReminderScheduler(),
            kind: .dailyReady,
            content: ReminderContent(title: "t", body: "b"),
            getFireTime: { (hour: 9, minute: 0) },
            setFireTime: { _ in }
        )
        // Seed `status` synchronously before mount so the section renders the
        // target row on the very first frame — the section's own `.task`
        // re-runs `onAppear()` on mount, which is idempotent here.
        await model.onAppear()
        return model
    }

    #if canImport(AppKit)
    /// Render the Reminders section alone, mirroring the production
    /// composition in `SettingsScreen` (`ReminderSettingsSection(model:...)`).
    @MainActor
    private func remindersSection(model: ReminderSettingsModel) -> some View {
        Form {
            ReminderSettingsSection(
                model: model,
                tintColor: DefaultTheme().accent.primary.resolved,
                copy: sectionCopy,
                primerCopy: primerCopy,
                deniedCopy: deniedCopy
            )
        }
        .formStyle(.grouped)
    }

    /// `enableRow`: the in-app instant-toggle row (baseline, unchanged by #880).
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotIPhoneLightNotDetermined() async {
        let model = await makeModel(status: .notDetermined)
        let host = hostingView(
            remindersSection(model: model),
            size: CGSize(width: 393, height: 200),
            colorScheme: .light
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "ReminderSettingsSection-iPhone-light-notDetermined")
        }
    }

    /// `deniedRow`: the deep-link-out row — pins the #880 trailing
    /// `arrow.up.forward.square` glyph that now distinguishes it from
    /// `enableRow` at a glance.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotIPhoneLightDenied() async {
        let model = await makeModel(status: .denied)
        let host = hostingView(
            remindersSection(model: model),
            size: CGSize(width: 393, height: 200),
            colorScheme: .light
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "ReminderSettingsSection-iPhone-light-denied")
        }
    }
    #endif
}
