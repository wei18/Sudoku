import SwiftUI
import Testing
@testable import SettingsUI
import Reminders

// MARK: - SettingsScreen (issue #421)
//
// The shared Settings page body, extracted from SudokuUI.SettingsView +
// MinesweeperUI.SettingsView, whose `body` assembled the SAME shell + 5 sections
// in the SAME order. These tests pin two contracts:
//   1. monetization-decoupling — `SettingsScreen` instantiates with an INJECTED
//      `purchases` @ViewBuilder slot and plain config, with NO MonetizationUI /
//      MonetizationCore / GameCenter / IAP / AdMob types in scope here, so it
//      can be mounted by either game (compile-only sentinel, mirrors the sibling
//      CompletionScreen + NavigationStackHost sentinels). If a future change
//      re-couples the body to MonetizationUI, this target stops compiling
//      (GameShellUITests does NOT link MonetizationUI).
//   2. both divergences both apps need build — Sudoku's About `aboutExtraRows`
//      slot (the Sudoku-only Generator row) AND the MS path that injects nothing
//      (EmptyView default), across the optional reminder + notices config.
//
// Pixel-level verification of the assembled screen lives in the apps' existing
// snapshot suites (SudokuUITests.SettingsViewTests full-page snapshots), which
// render through the real wrappers; keeping those baselines byte-identical is the
// regression guard for this refactor.

@Suite("GameShellUI — SettingsScreen")
@MainActor
struct SettingsScreenTests {

    private static func reminderConfig() -> SettingsScreenReminderConfig {
        let model = ReminderSettingsModel(
            permissionModel: ReminderPermissionModel(authorizer: NoopNotificationAuthorizing()),
            scheduler: NoopReminderScheduler(),
            kind: .dailyReady,
            content: ReminderContent(title: "t", body: "b"),
            getFireTime: { (hour: 9, minute: 0) },
            setFireTime: { _ in }
        )
        return SettingsScreenReminderConfig(
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
    }

    private static let notices = SettingsNoticesConfig(
        onAcknowledgements: {},
        privacyPolicyURL: URL(string: "https://example.com/privacy"),
        supportURL: URL(string: "https://example.com/support"),
        copyright: "© 2026 Wei"
    )

    // MARK: - Minimal (MS-shaped): no reminders, no notices, EmptyView slots

    @Test func minimalConstruction() {
        let screen = SettingsScreen(
            version: "1.0.0",
            tint: .accentColor,
            clearCache: {},
            purchases: { EmptyView() }
        )
        _ = screen.body
    }

    // MARK: - Game Center slot

    @Test func gameCenterSlot_rendersWhenInjected() {
        // When `onGameCenter` is non-nil the shared Game Center section is
        // included in the Form. Sentinel: body builds without crashing.
        var tapped = false
        let screen = SettingsScreen(
            version: "1.0.0",
            tint: .accentColor,
            clearCache: {},
            onGameCenter: { tapped = true },
            purchases: { EmptyView() }
        )
        _ = screen.body
        _ = tapped // silence unused-variable warning
    }

    @Test func gameCenterSlot_omittedWhenNil() {
        // `onGameCenter` defaults to nil — no Game Center section rendered.
        // Byte-identical to minimalConstruction; previews / tests stay inert.
        let screen = SettingsScreen(
            version: "1.0.0",
            tint: .accentColor,
            clearCache: {},
            purchases: { EmptyView() }
        )
        _ = screen.body
    }

    // MARK: - MS path with a Purchases slot but no About extra rows

    @Test func purchasesSlotNoAboutExtras() {
        let screen = SettingsScreen(
            version: "1.0.0",
            tint: .accentColor,
            clearCache: {},
            notices: Self.notices,
            purchases: {
                // Stands in for the app's MonetizationUI Purchases Section —
                // a plain SwiftUI view, NOT a MonetizationUI type.
                Section("Purchases") { Text("Remove Ads") }
            }
        )
        _ = screen.body
    }

    // MARK: - #744: Share App / Write a Review / Invite Friends

    @Test func appStoreRows_omittedWhenAppStoreIDNil() {
        // Byte-identical to minimalConstruction — `appStoreID` defaults nil,
        // so neither row is built. Sentinel: body builds without crashing.
        let screen = SettingsScreen(
            version: "1.0.0",
            tint: .accentColor,
            clearCache: {},
            purchases: { EmptyView() }
        )
        _ = screen.body
    }

    @Test func appStoreRows_renderWhenAppStoreIDValid() {
        // A pinned FAKE id (not Bundle.main) — proves the rows mount when the
        // host injects a resolved id, independent of any real xcconfig/Info.plist.
        let screen = SettingsScreen(
            version: "1.0.0",
            tint: .accentColor,
            clearCache: {},
            appStoreID: "1234567890",
            purchases: { EmptyView() }
        )
        _ = screen.body
    }

    @Test func appStoreRows_omittedWhenAppStoreIDUnresolvedToken() {
        // The shape Bundle.main reports pre-xcconfig-render — rows stay hidden.
        let screen = SettingsScreen(
            version: "1.0.0",
            tint: .accentColor,
            clearCache: {},
            appStoreID: "$(APP_STORE_ID)",
            purchases: { EmptyView() }
        )
        _ = screen.body
    }

    @Test func inviteFriendsRow_rendersWhenInjectedAlongsideGameCenter() {
        // The invite-friends row only renders inside the Game Center section
        // (i.e. only when `onGameCenter` is ALSO non-nil) — both injected here.
        var tapped = false
        let screen = SettingsScreen(
            version: "1.0.0",
            tint: .accentColor,
            clearCache: {},
            onGameCenter: {},
            presentInviteFriends: { tapped = true },
            purchases: { EmptyView() }
        )
        _ = screen.body
        _ = tapped // silence unused-variable warning
    }

    @Test func telemetryEmit_defaultsToNoOp() {
        // Default `{ _ in }` — constructing/rendering without injecting a
        // telemetry closure must not crash (previews / tests stay inert).
        let screen = SettingsScreen(
            version: "1.0.0",
            tint: .accentColor,
            clearCache: {},
            appStoreID: "1234567890",
            purchases: { EmptyView() }
        )
        _ = screen.body
    }

    // MARK: - Sudoku path: injects the Generator About extra row + reminders

    @Test func sudokuShapedWithAboutExtraRowsAndReminders() {
        let screen = SettingsScreen(
            version: "2.5.0",
            tint: .accentColor,
            clearCache: {},
            reminderSettings: Self.reminderConfig(),
            notices: Self.notices,
            purchases: {
                Section("Purchases") { Text("Remove Ads") }
            },
            aboutExtraRows: {
                // Sudoku's Sudoku-only Generator row.
                HStack { Text("Generator"); Spacer(); Text("v1") }
            }
        )
        _ = screen.body
    }
}
