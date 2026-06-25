// CompletionOverlayScaffold — the shared post-game overlay layout (#615).
//
// Extracted from Sudoku's BoardView+Completion (#610 fix) so Minesweeper —
// and every future game — gets the SAME centred-card + bottom-pinned Close
// treatment instead of each board hand-rolling its own surface. The per-app
// drift this removes is exactly what #615 surfaced: MS shipped a top-pinned
// card with a system-blue Close while Sudoku had the centred, accent-tinted,
// warm-paper version. One shared scaffold = no next drift (mirror principle).
//
// What it owns:
//   - the themed warm-paper background, extended behind the status bar / home
//     indicator via `.ignoresSafeArea()` (background layer ONLY — the card and
//     button stay within the safe area so the hero icon clears the Dynamic
//     Island, the #518 split).
//   - vertical centring of the result card. The card is wrapped in
//     `.fixedSize(horizontal: false, vertical: true)` so the shared
//     `CompletionScreen`'s own `.frame(maxHeight: .infinity)` can't expand to
//     fill the height and collapse the top Spacer (the #610 top-stick bug).
//   - a full-width, accent-tinted Close button pinned to the bottom safe area.
//
// What the caller owns: the card content (each game's Completion view) and the
// `onClose` action — Sudoku and MS both clear their overlay VM then `dismiss()`
// the presenting fullScreenCover so the player returns to the hub.

public import SwiftUI

public struct CompletionOverlayScaffold<Card: View>: View {
    @Environment(\.theme) private var theme

    private let onClose: () -> Void
    @ViewBuilder private let card: () -> Card

    public init(
        onClose: @escaping () -> Void,
        @ViewBuilder card: @escaping () -> Card
    ) {
        self.onClose = onClose
        self.card = card
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            theme.surface.background.resolved
                .ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                card()
                    // Prevent CompletionScreen's `.frame(maxHeight: .infinity)`
                    // from eating the Spacers and sticking the card at the top.
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(action: onClose) {
                    Text("Close", bundle: .main)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent.primary.resolved)
                .controlSize(.large)
                .padding(.horizontal, 32)
                .padding(.bottom, 16)
            }
        }
    }
}
