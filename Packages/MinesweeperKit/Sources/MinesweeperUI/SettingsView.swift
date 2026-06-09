// SettingsView — Minesweeper Settings.
//
// Wraps `GameShellUI.SettingsShellView` to inherit the shared grouped-Form
// chrome (PR X4).
//
// MS monetization wire Phase 3 (2026-06-03): mounts the shared
// `RemoveAdsRow` / `AdsRemovedRow` / `RestorePurchasesRow` from
// `MonetizationUI` (PR #249) under a `Section("Purchases")`. The host
// passes a `MonetizationStateController` constructed against the MS ASC
// productId. Tint is `.accentColor` — MS has no theme tokens yet.
//
// #277: drops the "Coming soon" stub. About(Version) + Storage(Clear cache)
// now reuse the shared `GameShellUI.SettingsAboutVersionRow` /
// `SettingsStorageSection` — the same building blocks Sudoku adopts. The host
// (LiveRouteFactory) supplies the version string (Bundle.main) and an async
// clear-cache closure wired to MS persistence via `PersistenceProtocol`.
// Clear-cache is parity-only until MS save-flow lands (latestInProgress()
// returns nil today), but it IS wired to the real protocol method, not a
// fake button. Tint is `.accentColor` — MS has no theme.

public import SwiftUI
public import MonetizationUI
// refactor/settingskit-target (2026-06-09): `SettingsScreen` /
// `SettingsNoticesConfig` + the reminders UI types moved out of GameShellUI into
// SettingsUI. `public` because `SettingsNoticesConfig` +
// `MinesweeperReminderSettingsEntry`'s copy types appear in public signatures.
public import SettingsUI

public struct SettingsView: View {
    private let version: String
    private let clearCache: @MainActor () async -> Void
    private let monetizationController: MonetizationStateController?
    // #331: shared Notices section inputs, app-injected by the host. Defaulted
    // nil so previews / tests keep the byte-identical screen.
    private let notices: SettingsNoticesConfig?
    // #287: shared Reminders entry (enable / prime permission / fire-time),
    // mirroring Sudoku. Defaulted nil so previews / tests mount a byte-identical
    // screen without the section; the host (LiveRouteFactory) injects one wired
    // to the RemindersKit Live conformers.
    private let reminderSettings: MinesweeperReminderSettingsEntry?
    // #330 P2: shared Sound section model (mute / volumes / BGM / haptics).
    // Defaulted nil so previews / tests keep the byte-identical screen without the
    // section; the host (LiveRouteFactory) injects the live-player-backed model.
    private let audioSettings: AudioSettingsModel?

    public init(
        version: String = "1.0.0",
        clearCache: @escaping @MainActor () async -> Void = {},
        monetizationController: MonetizationStateController? = nil,
        notices: SettingsNoticesConfig? = nil,
        reminderSettings: MinesweeperReminderSettingsEntry? = nil,
        audioSettings: AudioSettingsModel? = nil
    ) {
        self.version = version
        self.clearCache = clearCache
        self.monetizationController = monetizationController
        self.notices = notices
        self.reminderSettings = reminderSettings
        self.audioSettings = audioSettings
    }

    public var body: some View {
        // #421: the shared assembly (shell + 5 sections in order) now lives in
        // `GameShellUI.SettingsScreen`. MS supplies its config + the Purchases
        // slot, injects NO About extra rows (no generator), and tints with
        // `.accentColor` (MS has no theme tokens yet).
        SettingsScreen(
            version: version,
            tint: .accentColor,
            clearCache: clearCache,
            reminderSettings: reminderSettings.map {
                // #287: same building block Sudoku mounts; map the MS entry into
                // the shell's config.
                SettingsScreenReminderConfig(
                    model: $0.model,
                    copy: $0.copy,
                    primerCopy: $0.primerCopy,
                    deniedCopy: $0.deniedCopy
                )
            },
            audioSettings: audioSettings,
            notices: notices
        ) {
            // Purchases slot — the app's MonetizationUI rows. GameShellUI never
            // imports MonetizationUI; the whole conditional Section lives here.
            if let controller = monetizationController {
                Section("Purchases") {
                    if controller.hasPurchasedRemoveAds {
                        AdsRemovedRow(tintColor: .accentColor)
                    } else {
                        RemoveAdsRow(
                            controller: controller,
                            tintColor: .accentColor
                        )
                    }
                    RestorePurchasesRow(
                        controller: controller,
                        tintColor: .accentColor
                    )
                }
            }
        }
        // No `aboutExtraRows` — MS has no generator row (EmptyView default).
        .task {
            if let controller = monetizationController {
                await controller.bootstrap()
            }
        }
    }
}

/// #287: bundle of the shared `ReminderSettingsModel` + the MS-localized copy the
/// `ReminderSettingsSection` needs. Built at the composition root
/// (`LiveRouteFactory`) so all reminder wiring stays there; the view receives a
/// ready-to-mount value. Mirrors `SudokuUI.ReminderSettingsEntry`. Not
/// `Sendable` — carries `LocalizedStringKey` copy built + consumed on `@MainActor`.
public struct MinesweeperReminderSettingsEntry {
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

#Preview {
    NavigationStack {
        SettingsView()
    }
}
