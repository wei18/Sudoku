// MakeGameApp+Modifiers — universal root-view modifiers (#557 / #513).
//
// Extracted from MakeGameApp.swift to keep that file under the SwiftLint
// file_length ceiling (400). This modifier wraps the returned GameRoot view
// with the theme-tinted ATT priming sheet, presented from this outer view so
// it sits above the full app (not from inside the 50pt banner slot). #557
// review fix: the game's resolved `\.theme` tokens are threaded in as Color
// params so the sheet stays on-theme (Sudoku sage-green, not system blue) —
// MonetizationUI can't read `\.theme`, so colors are injected, mirroring
// BannerSlotView's param pattern. Matches pre-#557 SudokuUI.ATTPrimerSheet
// theming.
//
// #685: the GC-signed-out alert used to live here too, bound to the stable
// `GameRootViewModel` flag. That worked for the flag's *storage* but not its
// *presentation* — this helper is called exactly once from the plain
// `makeGameApp` function, never from inside a SwiftUI View's own `body`, so
// the Observable flag flip never got picked back up by the render graph
// (confirmed via instrumented sim repro). The alert now lives directly in
// `GameRoot.body`, alongside the `fullScreenCover` binding that already
// worked via the same @Observable-flag pattern — see `GameRoot.swift`.

internal import SwiftUI
internal import GameShellUI
internal import MonetizationUI

extension View {
    /// Applies the theme-tinted ATT primer sheet that every game's root view
    /// carries. See file header for the #557 rationale.
    @MainActor
    func universalRootModifiers(
        theme: any Theme,
        attPrimer: ATTPrimerCoordinator
    ) -> some View {
        self
            .attPrimerSheet(
                attPrimer,
                accentColor: theme.accent.primary.resolved,
                primaryTextColor: theme.text.primary.resolved,
                secondaryTextColor: theme.text.secondary.resolved,
                backgroundColor: theme.surface.background.resolved
            )
    }
}
