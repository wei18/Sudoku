// SettingsView — native Form with Account / Statistics / Storage / About.
//
// Per docs/designs/08-settings.md. No branding; HIG default Form chrome.
//
// v2.3.6: a new "Remove Ads" Section hosts two rows (Remove Ads CTA hidden
// once purchased; Restore Purchases always visible). Both rows flip to a
// `ProgressView` while the underlying async call is in flight.
//
// v2.4.6: purchase/restore success/failure and clear-cache confirmation
// surface via `ToastController` (bottom-center capsule, mounted on
// `RootView`) instead of orphan `Label` rows in the Form. `latestMessage`
// on the controller stays as the VoiceOver source of truth; the visual
// surface is the toast overlay.
//
// MS monetization wire Phase 1 (2026-06-02): the IAP rows
// (`RemoveAdsRow` / `AdsRemovedRow` / `RestorePurchasesRow`) moved to the
// shared `MonetizationUI` target in `AppMonetizationKit`. SettingsView now
// resolves `theme.accent.primary.resolved` and passes it as `tintColor:`
// at each row's init site — the shared rows have no `@Environment(\.theme)`
// dep of their own so Minesweeper can mount the same rows under a different
// palette in Phase 3.

// `@Environment(\.theme)` (the Theme env key from GameShellUI) is read only in
// the view bodies, not in any public signature, so this import is internal.
internal import GameShellUI
// refactor/settingskit-target: the shared `SettingsScreen` / `SettingsShellView`
// + the reminders UI types (`ReminderSettingsModel`, the copy value types,
// `SettingsNoticesConfig`) moved out of GameShellUI into SettingsUI. `public`
// because `ReminderSettingsEntry` re-exposes those types in its API surface.
public import SettingsUI
public import MonetizationUI
public import SwiftUI

public struct SettingsView<Banner: View>: View {
    @Bindable private var viewModel: SettingsViewModel
    private let monetizationController: MonetizationStateController?
    // #287: optional so previews / tests mount a byte-identical Settings screen
    // without the reminder section. Live wiring injects one + its copy so the
    // shared `ReminderSettingsSection` (enable / prime permission / time picker)
    // renders. Replaces the #321 time-only row with the shared GameShellUI
    // section so Minesweeper mirrors the identical entry.
    private let reminderSettings: ReminderSettingsEntry?
    // #331: shared Notices section inputs. Defaulted so previews / tests mount
    // a byte-identical screen without the section; the host (RouteFactory)
    // injects the app-specific URLs + copyright + acknowledgements deep-link.
    private let notices: SettingsNoticesConfig?
    // #330 P2: the shared audio settings model (volumes / mute / music / haptics).
    // `nil` in previews / tests → no audio section, byte-identical screen. Live
    // wiring injects one whose setters fan out to the running `LiveSoundPlayer`.
    private let audioSettings: AudioSettingsModel?
    // Epic 5: optional banner slot below the Form. SettingsKit / GameShellUI
    // must NOT import MonetizationUI; the actual BannerSlotView is injected by
    // LiveRouteFactory. EmptyView default keeps previews/tests inert.
    private let banner: Banner
    @Environment(\.theme) private var theme

    public init(
        viewModel: SettingsViewModel,
        monetizationController: MonetizationStateController? = nil,
        reminderSettings: ReminderSettingsEntry? = nil,
        notices: SettingsNoticesConfig? = nil,
        audioSettings: AudioSettingsModel? = nil,
        @ViewBuilder banner: () -> Banner = { EmptyView() }
    ) {
        self.viewModel = viewModel
        self.monetizationController = monetizationController
        self.reminderSettings = reminderSettings
        self.notices = notices
        self.audioSettings = audioSettings
        self.banner = banner()
    }

    public var body: some View {
        // #421: the shared assembly (shell + 5 sections in order) now lives in
        // `GameShellUI.SettingsScreen`. This wrapper supplies the Sudoku config
        // + the two injected slots (Purchases rows, the Sudoku-only Generator
        // About row) and the host-specific `.task` side-effects.
        SettingsScreen(
            version: viewModel.appVersion,
            tint: theme.accent.primary.resolved,
            clearCache: { await viewModel.clearCache() },
            reminderSettings: reminderSettings.map {
                // #287: shared Reminders section — same building block both apps
                // mount; map the Sudoku entry into the shell's config.
                SettingsScreenReminderConfig(
                    model: $0.model,
                    copy: $0.copy,
                    primerCopy: $0.primerCopy,
                    deniedCopy: $0.deniedCopy
                )
            },
            // #330 P2: the shared audio section (renders only when non-nil).
            audioSettings: audioSettings,
            notices: notices,
            // Game Center entry: present Apple's native GC dashboard (no leaderboard
            // focus — opens the full listing). `GameCenterDashboard` lives in this
            // module (SudokuUI/Leaderboard/GameCenterDashboard.swift); no extra import.
            onGameCenter: { GameCenterDashboard.present() },
            // Purchases slot — the app's MonetizationUI rows. GameShellUI never
            // imports MonetizationUI; the whole conditional Section lives here.
            purchases: {
                if let controller = monetizationController {
                    Section("Purchases") {
                        if controller.hasPurchasedRemoveAds {
                            AdsRemovedRow(tintColor: theme.accent.primary.resolved)
                        } else {
                            RemoveAdsRow(
                                controller: controller,
                                tintColor: theme.accent.primary.resolved
                            )
                        }
                        RestorePurchasesRow(
                            controller: controller,
                            tintColor: theme.accent.primary.resolved
                        )
                    }
                }
            },
            // #277: the Generator row is Sudoku-only (Minesweeper has no
            // generator). Injected into the shared About section after the
            // shared Version row, preserving the prior order exactly.
            aboutExtraRows: {
                AboutRow(systemImage: "gearshape", title: "Generator", value: generatorLabel)
            },
            // Epic 5: banner injected by LiveRouteFactory; EmptyView in previews/tests.
            banner: { banner }
        )
        .task { await viewModel.bootstrap() }
        .task {
            if let controller = monetizationController {
                await controller.bootstrap()
            }
        }
    }

    private var generatorLabel: String {
        // `GeneratorVersion.v1.rawValue` == `"v1"` — already prefixed.
        viewModel.generatorVersion.rawValue
    }
}

// MARK: - Reminder settings entry

/// #287: bundle of the shared `ReminderSettingsModel` + the Sudoku-localized
/// copy the `ReminderSettingsSection` needs. Built at the composition root
/// (`AppComposition.live()`) so all reminder wiring stays there; the view only
/// receives a ready-to-mount value. Not `Sendable` — carries `LocalizedStringKey`
/// copy built + consumed on `@MainActor`.
public struct ReminderSettingsEntry {
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

// MARK: - Rows

/// Static About row matching the icon-left / label / spacer / value-right
/// shape of `RemoveAdsRow` (now in MonetizationUI) so `.formStyle(.grouped)`
/// renders both sections with the same full-width pill background on macOS
/// (issue #197).
struct AboutRow: View {
    let systemImage: String
    let title: LocalizedStringKey
    let value: String
    @Environment(\.theme) private var theme

    var body: some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundStyle(theme.accent.primary.resolved)
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
