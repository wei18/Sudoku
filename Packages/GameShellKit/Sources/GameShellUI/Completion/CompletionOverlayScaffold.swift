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
//
// #652: optional `onPlayAgain` — when wired, renders "Play Again" (primary
// `.borderedProminent`) ABOVE Close (demoted to `.bordered`). When nil, only
// Close renders, preserving snapshot parity for callers that don't wire it.

public import SwiftUI

public struct CompletionOverlayScaffold<Card: View>: View {
    @Environment(\.theme) private var theme

    private let onClose: () -> Void
    // #652: Play Again CTA. `nil` → renders exactly as before (Close only).
    private let onPlayAgain: (() -> Void)?
    @ViewBuilder private let card: () -> Card

    public init(
        onClose: @escaping () -> Void,
        onPlayAgain: (() -> Void)? = nil,
        @ViewBuilder card: @escaping () -> Card
    ) {
        self.onClose = onClose
        self.onPlayAgain = onPlayAgain
        self.card = card
    }

    public var body: some View {
        // Unified centred layout, mirroring the pause "Leave Game?" card: the
        // result card and its CTAs form ONE group, vertically centred by the
        // ZStack (default `.center`). No GeometryReader/ScrollView — those
        // misbehave inside a board `.overlay` (the completion is presented as an
        // overlay on iPhone). The card is intrinsic-height, so the group sizes to
        // content and centres cleanly. Dynamic Type is capped on the card's hero
        // so the group can't overflow the screen. Every completion presentation —
        // both apps, overlay + pushed route — goes through here, staying identical.
        ZStack {
            theme.surface.background.resolved
                .ignoresSafeArea()
            // Section gap (#762 PR1 two-tier spacing contract) — structural,
            // fixed rhythm between the result card and its CTA group;
            // reinforced by the `.dynamicTypeSize` cap just below, which
            // exists specifically so this overlay can't grow past the
            // screen.
            VStack(spacing: theme.spacing.large) {
                card()
                ctas
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, theme.spacing.large)
            // Cap Dynamic Type so the (non-scrolling) group can't grow past the
            // screen — mirrors the board status bar's cap. Extreme-AX overflow
            // scroll is a possible follow-up; the cap keeps it on-screen.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        // #680: same board-leak defect as PauseOverlayView — the board
        // underneath stays LIVE in the a11y tree while this overlay presents.
        // `.isModal` alone isolates it (sim-verified via `idb ui describe-all`
        // on both apps: every board/digit-pad element drops out of the
        // reported tree, leaving only the hero + CTAs). Also applied to the
        // standalone pushed `.completion` route (macOS) — harmless there since
        // that route has no board sibling to begin with.
        .accessibilityAddTraits(.isModal)
    }

    @ViewBuilder
    private var ctas: some View {
        // spacing-exempt: 12pt (gap between full-width CTA buttons) predates
        // the 5-tier `SpacingTokens` scale — no matching tier to route
        // through without snapping to a neighbor and changing this
        // overlay's existing layout/snapshot. Tracked as a follow-up once
        // the token-scale gap gets an owner decision (#762).
        VStack(spacing: 12) {
            if let onPlayAgain {
                Button(action: onPlayAgain) {
                    // #797: `.foregroundStyle` MUST sit on the label content
                    // here, not chained after `.buttonStyle` below —
                    // `.borderedProminent` resolves its own white label ink
                    // internally and ignores an ambient `.foregroundStyle` set
                    // on the Button itself (sim-verified: chaining it outside
                    // rendered white, unchanged). That system-default white
                    // hard-fails AA against the dark-mode accent.primary on
                    // BOTH apps' ramps (Sudoku sage 0x9BB87E = 2.20:1; MS blue
                    // 0x7FAFCF = 2.35:1). Same #786 pattern: `surface.primary`
                    // clears 4.5:1 on every accent ramp this scaffold is themed
                    // with (Sudoku 4.83/7.42, MS 5.70/6.96 — light/dark). Light
                    // mode renders byte-identically (still white on every theme).
                    Text("Play Again", bundle: .main)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(theme.surface.primary.resolved)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent.primary.resolved)
                .controlSize(.large)
            }
            // #652: Close is demoted to secondary `.bordered` style when Play
            // Again is present; primary `.borderedProminent` when it is the only
            // CTA (nil onPlayAgain). Swift requires separate branches because
            // `.bordered` / `.borderedProminent` are different types.
            if onPlayAgain != nil {
                Button(action: onClose) {
                    Text("Close", bundle: .main)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(theme.accent.primary.resolved)
                .controlSize(.large)
                // #935 N10/N11: stable, non-localized anchor so the
                // host-driven XCUITest E2E flow can dismiss the completion
                // overlay in any locale — mirrors "game.completion.hero".
                .accessibilityIdentifier("game.completion.close")
            } else {
                Button(action: onClose) {
                    // #797: same on-accent-ink fix + placement requirement as
                    // the "Play Again" CTA above.
                    Text("Close", bundle: .main)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(theme.surface.primary.resolved)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent.primary.resolved)
                .controlSize(.large)
                // #935 N10/N11: see identical rationale above.
                .accessibilityIdentifier("game.completion.close")
            }
        }
        .padding(.horizontal, theme.spacing.small)
    }
}
