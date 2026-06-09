// MinesweeperSettingsViewTests — sentinel coverage for the MS SettingsView.
//
// 2026-06-03 (MS monetization wire Phase 3): SettingsView renders Purchases
// rows when a `MonetizationStateController` is injected. These tests confirm
// both code paths construct without crashing.
//
// #277: SettingsView now also mounts the shared
// `GameShellUI.SettingsAboutVersionRow` / `SettingsStorageSection` (the
// "Coming soon" stub is gone). Construction stays the same via defaults.
//
// No snapshot infra this round (defer per Track A precedent).

import SwiftUI
import Testing
@testable import MinesweeperAppComposition
// refactor/settingskit-target: `SettingsScreen` + the reminder copy/model types
// moved out of GameShellUI into SettingsUI.
import SettingsUI
import MinesweeperUI
import MonetizationUI
import Reminders

@MainActor
@Suite struct MinesweeperSettingsViewTests {

    @Test func settingsViewConstructsWithoutController() {
        // No monetization controller → Purchases section omitted; About +
        // Storage shared sections still render (defaults: version "1.0.0",
        // no-op clearCache).
        let view = SettingsView()
        _ = view.body
    }

    @Test func settingsViewConstructsWithPreviewBagController() {
        // Controller from `.preview()` is wired against
        // `minesweeperRemoveAdsProductId` and FakeIAPClient.
        let bag = MinesweeperAppComposition.preview()
        let view = SettingsView(monetizationController: bag.monetizationController)
        _ = view.body
    }

    @Test func settingsViewConstructsWithNoticesSection() {
        // #331: injecting a populated notices config mounts the shared
        // SettingsNoticesSection. Confirms the wired path builds.
        let view = SettingsView(
            notices: SettingsNoticesConfig(
                onAcknowledgements: {},
                privacyPolicyURL: URL(string: "https://example.com/privacy"),
                supportURL: URL(string: "https://example.com/support"),
                copyright: "© 2026 Wei"
            )
        )
        _ = view.body
    }

    @Test func settingsViewConstructsWithReminderSection() {
        // #287: injecting a reminder entry mounts the shared
        // `ReminderSettingsSection` (enable / prime permission / time picker).
        // Built over the Noop reminder conformers — no system center touched.
        let model = ReminderSettingsModel(
            permissionModel: ReminderPermissionModel(authorizer: NoopNotificationAuthorizing()),
            scheduler: NoopReminderScheduler(),
            kind: .dailyReady,
            content: ReminderContent(title: "t", body: "b"),
            getFireTime: { (hour: 9, minute: 0) },
            setFireTime: { _ in }
        )
        let entry = MinesweeperReminderSettingsEntry(
            model: model,
            copy: ReminderSettingsCopy(
                sectionTitle: "Reminders",
                enableTitle: "Daily reminder",
                enableCTA: "Turn On",
                enabledTitle: "Daily reminder",
                enabledStatus: "On",
                disableTitle: "Turn off reminders",
                timeTitle: "Time",
                deniedTitle: "Notifications are off",
                deniedCTA: "Fix"
            ),
            primerCopy: ReminderPrimerCopy(
                title: "t", lede: "l", bullets: ["b"],
                acceptCTA: "a", declineCTA: "d", fineprint: "f"
            ),
            deniedCopy: ReminderDeniedCopy(
                title: "t", message: "m", openSettingsCTA: "o",
                dismissCTA: "d", macOSGuidance: "g"
            )
        )
        let view = SettingsView(reminderSettings: entry)
        _ = view.body
    }
}
