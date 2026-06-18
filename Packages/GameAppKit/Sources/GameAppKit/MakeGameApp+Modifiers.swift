// MakeGameApp+Modifiers — universal root-view modifiers (#557 / #513).
//
// Extracted from MakeGameApp.swift to keep that file under the SwiftLint
// file_length ceiling (400). These modifiers wrap the returned GameRoot view:
//   - GC-signed-out alert, bound to the STABLE GameRootViewModel flag (not a
//     transient HomeVM property — the swiftui-interaction-footguns
//     "computed-property VM" footgun where an alert on a per-render VM never
//     fires). Mounting here keeps the binding alive across re-renders.
//   - ATT priming sheet, presented from this outer view so it sits above the
//     full app (not from inside the 50pt banner slot). #557 review fix: the
//     game's resolved `\.theme` tokens are threaded in as Color params so the
//     sheet stays on-theme (Sudoku sage-green, not system blue) — MonetizationUI
//     can't read `\.theme`, so colors are injected, mirroring BannerSlotView's
//     param pattern. Matches pre-#557 SudokuUI.ATTPrimerSheet theming.

internal import SwiftUI
internal import GameShellUI
internal import MonetizationUI

extension View {
    /// Applies the GC-signed-out alert + theme-tinted ATT primer sheet that every
    /// game's root view carries. See file header for the #513 / #557 rationale.
    @MainActor
    func universalRootModifiers<Route: Hashable & Sendable>(
        rootViewModel: GameRootViewModel<Route>,
        theme: any Theme,
        attPrimer: ATTPrimerCoordinator
    ) -> some View {
        self
            .alert(
                "Sign in to Game Center",
                isPresented: Binding(
                    get: { rootViewModel.showGameCenterSignedOutAlert },
                    set: { rootViewModel.showGameCenterSignedOutAlert = $0 }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Sign in to Game Center to compare with others.")
            }
            .attPrimerSheet(
                attPrimer,
                accentColor: theme.accent.primary.resolved,
                primaryTextColor: theme.text.primary.resolved,
                secondaryTextColor: theme.text.secondary.resolved,
                backgroundColor: theme.surface.background.resolved
            )
    }
}
