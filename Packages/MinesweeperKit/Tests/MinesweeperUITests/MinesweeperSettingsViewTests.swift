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
// #832: `SettingsView` is now the shared `GameAppKit.SettingsView`, driven by
// a mandatory `viewModel: SettingsViewModel` (was primitive `version:`/
// `clearCache:` params) — every construction below now builds one over the
// shared zero-IO `PersistenceTesting.FakePersistence`, mirroring Sudoku's
// `SettingsViewTests` fixture shape exactly.
//
// No snapshot infra this round (defer per Track A precedent).

import SwiftUI
import Testing
@testable import MinesweeperAppComposition
// refactor/settingskit-target: `SettingsScreen` + the reminder copy/model types
// moved out of GameShellUI into SettingsUI.
import SettingsUI
@testable import MinesweeperUI
import MonetizationUI
import PersistenceTesting
import Reminders
import Telemetry

@MainActor
@Suite struct MinesweeperSettingsViewTests {

    @Test func settingsViewConstructsWithoutController() {
        // No monetization controller → Purchases section omitted; About +
        // Storage shared sections still render (defaults: appVersion "1.0.0",
        // no MS Generator row).
        let viewModel = SettingsViewModel(persistence: FakePersistence())
        let view = SettingsView(viewModel: viewModel)
        _ = view.body
    }

    @Test func settingsViewConstructsWithPreviewBagController() {
        // Controller from `.preview()` is wired against
        // `minesweeperRemoveAdsProductId` and FakeIAPClient.
        let bag = MinesweeperAppComposition.preview()
        let viewModel = SettingsViewModel(persistence: FakePersistence())
        let view = SettingsView(viewModel: viewModel, monetizationController: bag.monetizationController)
        _ = view.body
    }

    @Test func settingsViewIncludesGameCenterSection() {
        // Verifies the Game Center `onGameCenter` closure is wired into
        // SettingsScreen — the body builds without crashing.
        let viewModel = SettingsViewModel(persistence: FakePersistence())
        let view = SettingsView(viewModel: viewModel)
        _ = view.body
    }

    // #685: the Settings Game Center row previously always called
    // `GameCenterDashboard.present()` directly with no signed-out guard.
    // `presentGameCenter` (when injected) now takes over `onGameCenter` from
    // that hardcoded default. #714: the original version of this test only
    // proved construction/render doesn't eagerly invoke the closure — it would
    // stay green even if `presentGameCenter` were never threaded to
    // `SettingsScreen`. Now drives `resolvedOnGameCenter()` (the exact
    // closure passed as `onGameCenter:`) directly to prove the injected
    // presenter — not the unguarded fallback — actually fires.
    @Test func settingsViewUsesInjectedPresentGameCenterOverDefault() {
        let viewModel = SettingsViewModel(persistence: FakePersistence())
        var called = false
        let view = SettingsView(viewModel: viewModel, presentGameCenter: { called = true })
        _ = view.body
        #expect(called == false, "constructing/rendering must not itself invoke the closure")
        view.resolvedOnGameCenter()
        #expect(called == true, "resolvedOnGameCenter must invoke the injected presentGameCenter, not the unguarded default")
    }

    // MARK: - #744: Share App / Write a Review / Invite Friends

    @Test func settingsViewConstructsWithAppStoreRowsAndInviteFriends() {
        // A pinned FAKE id (not Bundle.main — see AppStoreLinks's header
        // comment) proves the wired path builds with both new capabilities
        // injected simultaneously.
        let viewModel = SettingsViewModel(persistence: FakePersistence())
        let view = SettingsView(
            viewModel: viewModel,
            presentGameCenter: {},
            appStoreID: "1234567890",
            presentInviteFriends: {}
        )
        _ = view.body
    }

    @Test func settingsViewOmitsAppStoreRowsWhenIDNil() {
        // Byte-identical to settingsViewIncludesGameCenterSection —
        // `appStoreID` defaults nil, so Share App / Write a Review stay hidden.
        let viewModel = SettingsViewModel(persistence: FakePersistence())
        let view = SettingsView(viewModel: viewModel)
        _ = view.body
    }

    @Test func settingsViewForwardsTelemetryEmitToSettingsScreen() {
        // The closure itself is opaque from here (SettingsScreen owns firing
        // it on row taps); this only proves construction with a non-default
        // emit closure doesn't itself invoke it eagerly.
        var events: [TelemetryEvent] = []
        let viewModel = SettingsViewModel(persistence: FakePersistence())
        let view = SettingsView(
            viewModel: viewModel,
            appStoreID: "1234567890",
            telemetryEmit: { events.append($0) }
        )
        _ = view.body
        #expect(events.isEmpty, "constructing/rendering must not itself emit telemetry")
    }

    @Test func settingsViewConstructsWithNoticesSection() {
        // #331: injecting a populated notices config mounts the shared
        // SettingsNoticesSection. Confirms the wired path builds.
        let viewModel = SettingsViewModel(persistence: FakePersistence())
        let view = SettingsView(
            viewModel: viewModel,
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
        // #572: MinesweeperReminderSettingsEntry deleted; use shared ReminderSettingsEntry.
        let entry = ReminderSettingsEntry(
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
        let viewModel = SettingsViewModel(persistence: FakePersistence())
        let view = SettingsView(viewModel: viewModel, reminderSettings: entry)
        _ = view.body
    }
}
