// ReminderSettingsSection — the shared Settings reminder entry (#287: "the
// reminders entry must be wired into the Settings screen").
//
// One `Section("Reminders")` shared by BOTH apps (Minesweeper mirrors Sudoku),
// driven by the shared `ReminderSettingsModel`. It is the user-initiated entry
// point to enabling daily reminders — distinct from the post-Daily primer.
//
// Rows shown depend on the system authorization status:
//   - .notDetermined  → an "Enable" button row. Tapping presents the shared
//                        `ReminderPrimerSheet` (soft pre-ask) → on accept the
//                        model fires the one-shot system prompt + schedules.
//   - .authorized /
//     .provisional    → a status row ("On") + the daily fire-time `DatePicker`.
//   - .denied         → a status row deep-linking to the recovery explainer
//                        (`ReminderDeniedExplainer`: Settings deep-link on iOS,
//                        textual guidance on macOS).
//
// Copy fully injected (`ReminderSettingsCopy` + the primer/denied copy) so the
// shared target hard-codes no app text (proposal §3.3). Tint injected as
// `Color` — NO `@Environment(\.theme)` dependency on the section itself, matching
// `SettingsNoticesSection` / `SettingsAboutVersionRow` so Minesweeper (no theme
// tokens) mounts the identical section under `.accentColor`. The presented
// primer/denied SHEETS read `@Environment(\.theme)` themselves and fall back to
// `NeutralTheme` when an app injects none.

public import SwiftUI

// MARK: - Copy value type (fully injected)

/// User-facing strings for the Settings reminder section's own rows (the primer +
/// denied explainer copy are passed separately via their existing value types).
/// `LocalizedStringKey` so each app's `Localizable.xcstrings` localizes the
/// literals passed at the call site. Not `Sendable` — `LocalizedStringKey` isn't,
/// and this is built + consumed entirely on `@MainActor`.
public struct ReminderSettingsCopy: Equatable {
    /// Section header, e.g. "Reminders".
    public var sectionTitle: LocalizedStringKey
    /// The enable-row label shown when not yet authorized, e.g. "Daily reminder".
    public var enableTitle: LocalizedStringKey
    /// The enable-row trailing CTA, e.g. "Turn On".
    public var enableCTA: LocalizedStringKey
    /// The status-row label once on, e.g. "Daily reminder".
    public var enabledTitle: LocalizedStringKey
    /// The trailing status text once on, e.g. "On".
    public var enabledStatus: LocalizedStringKey
    /// The turn-off row label shown once on, e.g. "Turn off reminders".
    public var disableTitle: LocalizedStringKey
    /// The fire-time picker label, e.g. "Time".
    public var timeTitle: LocalizedStringKey
    /// The status-row label when denied, e.g. "Notifications are off".
    public var deniedTitle: LocalizedStringKey
    /// The trailing CTA when denied, e.g. "Fix".
    public var deniedCTA: LocalizedStringKey

    public init(
        sectionTitle: LocalizedStringKey,
        enableTitle: LocalizedStringKey,
        enableCTA: LocalizedStringKey,
        enabledTitle: LocalizedStringKey,
        enabledStatus: LocalizedStringKey,
        disableTitle: LocalizedStringKey,
        timeTitle: LocalizedStringKey,
        deniedTitle: LocalizedStringKey,
        deniedCTA: LocalizedStringKey
    ) {
        self.sectionTitle = sectionTitle
        self.enableTitle = enableTitle
        self.enableCTA = enableCTA
        self.enabledTitle = enabledTitle
        self.enabledStatus = enabledStatus
        self.disableTitle = disableTitle
        self.timeTitle = timeTitle
        self.deniedTitle = deniedTitle
        self.deniedCTA = deniedCTA
    }
}

// MARK: - Section

public struct ReminderSettingsSection: View {
    @Bindable private var model: ReminderSettingsModel
    private let tintColor: Color
    private let copy: ReminderSettingsCopy
    private let primerCopy: ReminderPrimerCopy
    private let deniedCopy: ReminderDeniedCopy

    public init(
        model: ReminderSettingsModel,
        tintColor: Color,
        copy: ReminderSettingsCopy,
        primerCopy: ReminderPrimerCopy,
        deniedCopy: ReminderDeniedCopy
    ) {
        self.model = model
        self.tintColor = tintColor
        self.copy = copy
        self.primerCopy = primerCopy
        self.deniedCopy = deniedCopy
    }

    public var body: some View {
        Section(copy.sectionTitle) {
            switch model.status {
            case .authorized, .provisional:
                enabledStatusRow
                timeRow
                disableRow
            case .denied:
                deniedRow
            case .notDetermined:
                enableRow
            }
        }
        // Refresh status when the screen appears (the user may have toggled it in
        // Settings.app). `.task` re-fires per the swiftui-interaction-footguns
        // note only on identity change — fine here (one Settings mount).
        .task { await model.onAppear() }
        .sheet(isPresented: $model.isPrimerPresented) {
            ReminderPrimerSheet(
                copy: primerCopy,
                isRequesting: model.isRequesting,
                onAccept: { Task { await model.acceptPrimer() } },
                onDecline: { model.declinePrimer() }
            )
            // R6.3 (SDD-003): single fixed detent prevents drag-up layout
            // breakage; hidden indicator removes the affordance to drag at all.
            // The sheet is dismissed explicitly via "Not now" or accept only.
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $model.isDeniedExplainerPresented) {
            ReminderDeniedExplainer(
                copy: deniedCopy,
                onOpenSettings: { model.openSystemSettings() },
                onDismiss: { model.dismissDeniedExplainer() }
            )
            // R6.3 (SDD-003) + #673: same single-detent + hidden-indicator
            // treatment as the primer sheet above, for parity.
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
        }
    }

    // MARK: - Rows

    /// Not-yet-authorized: a tappable row whose trailing CTA opens the primer.
    /// The whole row is a `Button` so the 44pt hit target spans the cell
    /// (swiftui-interaction-footguns: a trailing-only tap shrinks the target).
    private var enableRow: some View {
        Button { model.enable() } label: {
            HStack {
                Image(systemName: "bell")
                    .foregroundStyle(tintColor)
                Text(copy.enableTitle)
                    .foregroundStyle(.primary)
                Spacer()
                Text(copy.enableCTA)
                    .foregroundStyle(tintColor)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reminders.settings.enable")
    }

    /// Authorized: a static "On" status row.
    private var enabledStatusRow: some View {
        HStack {
            Image(systemName: "bell.fill")
                .foregroundStyle(tintColor)
            Text(copy.enabledTitle)
            Spacer()
            Text(copy.enabledStatus)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// Authorized: the daily fire-time picker, restricted to hour+minute. The
    /// model's `fireDate.didSet` persists + reschedules.
    private var timeRow: some View {
        DatePicker(
            selection: $model.fireDate,
            displayedComponents: .hourAndMinute
        ) {
            Label {
                Text(copy.timeTitle)
            } icon: {
                Image(systemName: "clock")
                    .foregroundStyle(tintColor)
            }
        }
        .accessibilityIdentifier("reminders.settings.time")
    }

    /// Authorized: the in-app OFF affordance (#287 CR). Cancels the scheduled
    /// reminder via `model.disable()` so a player who turned reminders on can turn
    /// them back off without leaving the app. The whole row is the hit target
    /// (swiftui-interaction-footguns: a trailing-only tap shrinks the target); the
    /// destructive `.red` label signals the off action.
    private var disableRow: some View {
        Button(role: .destructive) {
            Task { await model.disable() }
        } label: {
            HStack {
                Image(systemName: "bell.slash")
                    .foregroundStyle(.red)
                Text(copy.disableTitle)
                    .foregroundStyle(.red)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reminders.settings.disable")
    }

    /// Denied: a tappable row opening the recovery explainer.
    private var deniedRow: some View {
        Button { model.showDeniedExplainer() } label: {
            HStack {
                Image(systemName: "bell.slash")
                    .foregroundStyle(tintColor)
                Text(copy.deniedTitle)
                    .foregroundStyle(.primary)
                Spacer()
                Text(copy.deniedCTA)
                    .foregroundStyle(tintColor)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reminders.settings.denied")
    }
}
