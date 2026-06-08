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

public import GameShellUI
public import MonetizationUI
public import SwiftUI

public struct SettingsView: View {
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
    @Environment(\.theme) private var theme

    public init(
        viewModel: SettingsViewModel,
        monetizationController: MonetizationStateController? = nil,
        reminderSettings: ReminderSettingsEntry? = nil,
        notices: SettingsNoticesConfig? = nil
    ) {
        self.viewModel = viewModel
        self.monetizationController = monetizationController
        self.reminderSettings = reminderSettings
        self.notices = notices
    }

    public var body: some View {
        SettingsShellView(title: "Settings") {
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

            // #287: shared Reminders section — the user-initiated entry to
            // enable daily reminders (primes the notification permission via the
            // shared `ReminderPrimerSheet`), set the fire time, and recover when
            // denied. Replaces the #321 time-only row; same building block
            // Minesweeper mounts so the entry is identical across both apps.
            if let reminderSettings {
                ReminderSettingsSection(
                    model: reminderSettings.model,
                    tintColor: theme.accent.primary.resolved,
                    copy: reminderSettings.copy,
                    primerCopy: reminderSettings.primerCopy,
                    deniedCopy: reminderSettings.deniedCopy
                )
            }

            Section("About") {
                // Issue #197: unify with Purchases section's HStack primitive
                // so `.formStyle(.grouped)` on macOS renders all rows as
                // full-width pills. `LabeledContent` lands on a 2-column
                // preferences layout that bypasses the pill background.
                //
                // #277: the Version row is now the shared
                // `GameShellUI.SettingsAboutVersionRow`. The Generator row is
                // Sudoku-only (Minesweeper has no generator) and stays here.
                SettingsAboutVersionRow(
                    version: viewModel.appVersion,
                    tintColor: theme.accent.primary.resolved
                )
                AboutRow(systemImage: "gearshape", title: "Generator", value: generatorLabel)
            }

            // #331: shared Notices / 宣告 section — acknowledgements deep-link,
            // privacy-policy + support links, copyright. URLs + copyright are
            // app-injected via the config; the shared section owns layout only.
            if let notices {
                SettingsNoticesSection(
                    tintColor: theme.accent.primary.resolved,
                    config: notices
                )
            }

            // #277: shared Storage section. Wires the existing VM clearCache.
            SettingsStorageSection(clearCache: { await viewModel.clearCache() })
        }
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
