// SettingsShellView — generic Settings Form chrome.
//
// Owns the cross-game Settings chrome: a grouped `Form` with a navigation
// title. The caller supplies the actual section content via a `@ViewBuilder`
// closure — Sudoku passes Purchases / About / Storage; Minesweeper (and a
// future third game) pass their own sections through the same shell.
//
// Extracted from `SudokuKit/SudokuUI/Settings/SettingsView.swift` (PR X4).
// Sudoku-specific bits (IAP rows, ClearCache action, About row content,
// theme references, ToastController wiring, ViewModel coupling) stay in
// `SudokuKit.SettingsView`, which now wraps this shell.
//
// Karpathy "no premature abstraction": the only thing genuinely shared
// across games is the `Form { ... }.formStyle(.grouped).navigationTitle(...)`
// triple. Section grouping, row primitives, and side-effect modifiers
// (.task / .confirmationDialog) all live in the caller — extracting them
// here would force every game into Sudoku's section taxonomy and side-effect
// shape, which neither Minesweeper nor a third game has agreed to.

public import SwiftUI

public struct SettingsShellView<Sections: View>: View {
    private let title: LocalizedStringKey
    private let sections: () -> Sections

    public init(
        title: LocalizedStringKey,
        @ViewBuilder sections: @escaping () -> Sections
    ) {
        self.title = title
        self.sections = sections
    }

    public var body: some View {
        Form {
            sections()
        }
        // `Form` on macOS inside NavigationSplitView's detail pane picks a
        // per-row layout based on the content primitive (Button → pill,
        // LabeledContent → 2-column preferences row, no pill background).
        // `.formStyle(.grouped)` forces grouped/pill treatment uniformly so
        // sibling sections all render as full-width pill rows. iOS Form
        // defaults to grouped in NavigationStack already, so this is a
        // no-op on iPhone. (Sudoku issue #197, carried into the shell.)
        .formStyle(.grouped)
        .navigationTitle(title)
    }
}
