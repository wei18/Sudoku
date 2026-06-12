// SettingsScreen — the shared Settings page BODY (#421).
//
// Extracted from SudokuUI.SettingsView + MinesweeperUI.SettingsView, whose
// `body` assembled the SAME shared GameShellUI blocks in the SAME order inside
// `SettingsShellView(title: "Settings")`:
//   1. Purchases    — injected `purchases` slot (the app's MonetizationUI rows)
//   2. Reminders    — `ReminderSettingsSection` (when `reminderSettings != nil`)
//   3. About        — `SettingsAboutVersionRow` + injected `aboutExtraRows` slot
//   4. Notices      — `SettingsNoticesSection` (when `notices != nil`)
//   5. Storage      — `SettingsStorageSection(clearCache:)`
//
// This is the shared *assembly*; each app keeps its OWN `SettingsView` wrapper
// that builds the config + slots and supplies the host-specific `.task`
// side-effects (Sudoku's ViewModel bootstrap, the monetization controller
// bootstrap). Everything app-divergent is INJECTED:
//   - `purchases` (@ViewBuilder) — the app's MonetizationUI Purchases rows.
//     GameShellUI must NOT import MonetizationUI; this stays a view slot so the
//     shell never gains an IAP / GameCenter / AdMob dependency (mirrors #418's
//     leaderboard-as-value-type decoupling).
//   - `aboutExtraRows` (@ViewBuilder, default EmptyView) — Sudoku injects its
//     Sudoku-only "Generator" row here; Minesweeper injects nothing.
//   - `banner` (@ViewBuilder, default EmptyView) — the app-injected
//     `BannerSlotView` (Epic 5). SettingsKit must NOT import MonetizationUI /
//     AppMonetizationKit; the actual slot is injected at the RouteFactory level.
//   - `version`, `reminderSettings`, `notices`, `clearCache`, `tint` — injected
//     config exactly as the prior wrappers passed them.
//
// Section titles ("Purchases" / "About" / …) stay `LocalizedStringKey` literals
// resolved from each host app's own `Localizable.xcstrings` (Bundle.main),
// byte-identical to the prior wrappers — no catalog change.

public import SwiftUI

public struct SettingsScreen<Purchases: View, AboutExtraRows: View, Banner: View>: View {
    private let purchases: () -> Purchases
    private let reminderSettings: SettingsScreenReminderConfig?
    private let audioSettings: AudioSettingsModel?
    private let version: String
    private let aboutExtraRows: () -> AboutExtraRows
    private let notices: SettingsNoticesConfig?
    private let clearCache: @MainActor () async -> Void
    private let tint: Color
    private let banner: () -> Banner

    public init(
        version: String,
        tint: Color,
        clearCache: @escaping @MainActor () async -> Void,
        reminderSettings: SettingsScreenReminderConfig? = nil,
        audioSettings: AudioSettingsModel? = nil,
        notices: SettingsNoticesConfig? = nil,
        @ViewBuilder purchases: @escaping () -> Purchases,
        @ViewBuilder aboutExtraRows: @escaping () -> AboutExtraRows = { EmptyView() },
        @ViewBuilder banner: @escaping () -> Banner = { EmptyView() }
    ) {
        self.version = version
        self.tint = tint
        self.clearCache = clearCache
        self.reminderSettings = reminderSettings
        self.audioSettings = audioSettings
        self.notices = notices
        self.purchases = purchases
        self.aboutExtraRows = aboutExtraRows
        self.banner = banner
    }

    public var body: some View {
        SettingsShellView(title: "Settings", sections: {
            // 1. Purchases — injected MonetizationUI rows. The slot is the whole
            // `Section("Purchases") { ... }` (or EmptyView when no controller),
            // built by the host, so the conditional + the IAP coupling stay in
            // the app and out of GameShellUI.
            purchases()

            // 2. Reminders — shared section (enable / prime permission / fire
            // time). Same building block both apps mount; injected copy.
            if let reminderSettings {
                ReminderSettingsSection(
                    model: reminderSettings.model,
                    tintColor: tint,
                    copy: reminderSettings.copy,
                    primerCopy: reminderSettings.primerCopy,
                    deniedCopy: reminderSettings.deniedCopy
                )
            }

            // 2b. Sound — shared audio section (mute / volumes / BGM / haptics).
            // Same building block both apps mount; rendered only when an audio
            // model is injected (#330 P1; nil keeps existing call sites compiling).
            if let audioSettings {
                AudioSettingsSection(model: audioSettings, tintColor: tint)
            }

            // 3. About — shared Version row + injected extra rows. Sudoku passes
            // its Sudoku-only "Generator" row via `aboutExtraRows`; MS passes
            // nothing (EmptyView default), so its About section holds only the
            // version row — byte-identical to before.
            Section("About") {
                SettingsAboutVersionRow(version: version, tintColor: tint)
                aboutExtraRows()
            }

            // 4. Notices — shared section; URLs + copyright injected via config.
            if let notices {
                SettingsNoticesSection(tintColor: tint, config: notices)
            }

            // 5. Storage — shared section. Wires the host-supplied clearCache.
            SettingsStorageSection(clearCache: clearCache)
        }, banner: banner)
    }
}

// MARK: - Reminder config

/// Bundle of the shared `ReminderSettingsModel` + the host-localized copy the
/// `ReminderSettingsSection` needs. Unifies the previously-duplicated
/// `SudokuUI.ReminderSettingsEntry` / `MinesweeperUI.MinesweeperReminderSettingsEntry`
/// (identical field-for-field) into one shell-owned value. Built at each app's
/// composition root so all reminder wiring stays there; the screen receives a
/// ready-to-mount value. Not `Sendable` — carries `LocalizedStringKey` copy
/// built + consumed on `@MainActor`.
public struct SettingsScreenReminderConfig {
    public let model: ReminderSettingsModel
    public let copy: ReminderSettingsCopy
    public let primerCopy: ReminderPrimerCopy
    public let deniedCopy: ReminderDeniedCopy

    public init(
        model: ReminderSettingsModel,
        copy: ReminderSettingsCopy,
        primerCopy: ReminderPrimerCopy,
        deniedCopy: ReminderDeniedCopy
    ) {
        self.model = model
        self.copy = copy
        self.primerCopy = primerCopy
        self.deniedCopy = deniedCopy
    }
}
