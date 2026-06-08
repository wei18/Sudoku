// ATTPrimerSheet — the ATT pre-prompt (priming) screen (#195).
//
// Shown BEFORE the system ATT dialog, at the first ad-relevant moment (see
// ATTPrimerCoordinator). Path-B copy: relevance not a profile; decline still
// works; or remove ads. "Continue" leads into the system dialog; "Not now"
// dismisses without requesting.
//
// Strings are `LocalizedStringKey`s resolved against the app's
// `Localizable.xcstrings` (main bundle) — the same resolution every other
// SudokuUI key uses (e.g. "Daily", "Remove Ads"). New keys ship in
// App/Sudoku/Resources/Localizable.xcstrings (7 locales). NOT in Minesweeper's
// catalog — this sheet is Sudoku-only.

public import SwiftUI

@MainActor
struct ATTPrimerSheet: View {
    @Bindable var coordinator: ATTPrimerCoordinator
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)

            Image(systemName: "hand.raised.circle")
                .font(.system(size: 56))
                .foregroundStyle(theme.accent.primary.resolved)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("att.primer.title")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.text.primary.resolved)

                Text("att.primer.body")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.text.secondary.resolved)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 12)

            VStack(spacing: 12) {
                Button {
                    Task { await coordinator.continueToSystemPrompt() }
                } label: {
                    Text("att.primer.continue")
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(theme.accent.primary.resolved)

                Button {
                    coordinator.declinePrimer()
                } label: {
                    Text("att.primer.notNow")
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .controlSize(.large)
                .foregroundStyle(theme.text.secondary.resolved)
            }
        }
        .padding(24)
        .background(theme.surface.background.resolved)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

extension View {
    /// Mounts the ATT priming sheet, presented when the coordinator's
    /// `isPrimerPresented` flips true. No-op when `coordinator` is nil (hosts
    /// that don't drive ATT, e.g. previews / Minesweeper-shaped composition).
    @MainActor
    @ViewBuilder
    func attPrimerSheet(_ coordinator: ATTPrimerCoordinator?) -> some View {
        if let coordinator {
            self.modifier(ATTPrimerSheetModifier(coordinator: coordinator))
        } else {
            self
        }
    }
}

private struct ATTPrimerSheetModifier: ViewModifier {
    @Bindable var coordinator: ATTPrimerCoordinator

    func body(content: Content) -> some View {
        content.sheet(isPresented: $coordinator.isPrimerPresented) {
            ATTPrimerSheet(coordinator: coordinator)
        }
    }
}
