// ReminderSettingsEntry — bundle of the reminder settings model + game-specific
// copy, threaded into the Settings screen.
//
// Moved from SudokuKit/Sources/SudokuUI/Settings/SettingsView.swift into
// SettingsUI (#556 SDD-005 Pillar B) so GameAppKit can reference it in
// `GameDeps` without creating a module cycle. All constituent types are already
// in SettingsUI; the entry struct itself has no new dependencies.

/// A bundle of the reminder settings model + game-specific localized copy,
/// assembled by the composition root and injected into `SettingsView`.
/// The model is game-agnostic (enable/prime permission/fire-time); the copy
/// is game-localized (section title, CTA labels, notification text).
/// `@MainActor` because the model is an `@Observable` class and both model +
/// copy are built + consumed on `@MainActor`.
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
