// CompletionOverlayScaffold — the shared post-game overlay layout (#615, G6
// rebuild #1023).
//
// Extracted from Sudoku's BoardView+Completion (#610 fix) so Minesweeper —
// and every future game — gets the SAME full-height glass panel + CTA
// hierarchy instead of each board hand-rolling its own surface. The per-app
// drift this removes is exactly what #615 surfaced.
//
// #1023 rebuild (docs/designs/v3/design.md §3.5, §4.3, §4.4): the previous
// opaque warm-paper background is GONE — G6 is now a full-height custom
// Liquid-Glass panel (the explicit exception ruled by D-3.3) with the
// finished board visible behind it (unlike pause, which must hide the board
// — completion has nothing left to hide). An accent glow is painted BEHIND
// the glass so the glass naturally picks up its tint (§3.5, `color.md:68`:
// glass has no inherent color). `variant` (`CompletionVariant`) gates the
// ritual + panel-rise motion (`CompletionMotionPlan`); `context`
// (`CompletionContext`) drives the exact CTA hierarchy from §3.5's 4-row
// table. Every completion presentation — both apps, live overlay + all 3
// review paths — goes through here, staying identical.
//
// #1023 §4.3 contract note: this scaffold mounting is the G6 half of the
// scene-exclusivity handoff with G4 (board control cluster, #1022, not yet
// built) — when this view appears, G4 must already be gone (unmount is
// #1022's job). `.boardModalOverlay(presentation: .completion)` is the seam
// #1022's G4-hide logic observes.
//
// What the caller owns: the card content (each game's Completion view), the
// `onClose` action, `variant`, and `context`. Sudoku and MS both clear their
// overlay VM then `dismiss()`/pop to return the player to the hub.

public import SwiftUI

public struct CompletionOverlayScaffold<Card: View>: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // #1023: mirrors `completionHeroSkipsReveal` — the panel-rise state below
    // is ALSO onAppear-driven, so it needs the same offline-renderer escape
    // hatch (snapshot tests / ASC screenshot emitter never fire `.onAppear`).
    @Environment(\.completionHeroSkipsReveal) private var skipsReveal

    private let variant: CompletionVariant
    private let outcomeKind: CompletionOutcome.Kind
    private let context: CompletionContext
    private let onClose: () -> Void
    @ViewBuilder private let card: () -> Card

    /// Panel-rise (M10) reveal latch — starts `false`, flips true on appear
    /// (or immediately for `.none`/skip-reveal), mirrors `CompletionScreen`'s
    /// `heroRevealed` pattern.
    @State private var panelRevealed = false

    public init(
        variant: CompletionVariant,
        outcomeKind: CompletionOutcome.Kind,
        context: CompletionContext,
        onClose: @escaping () -> Void,
        @ViewBuilder card: @escaping () -> Card
    ) {
        self.variant = variant
        self.outcomeKind = outcomeKind
        self.context = context
        self.onClose = onClose
        self.card = card
    }

    private var motionPlan: CompletionMotionPlan {
        CompletionMotionPlan.plan(variant: variant, outcomeKind: outcomeKind, reduceMotion: reduceMotion)
    }

    private var isPanelRevealed: Bool {
        if case .none = motionPlan.panelRise { return true }
        return panelRevealed || skipsReveal
    }

    public var body: some View {
        content
            .offset(y: panelOffsetY)
            .opacity(panelOpacity)
            .animation(panelAnimation, value: isPanelRevealed)
            // #680: same board-leak defect as PauseOverlayView — the board
            // underneath stays LIVE in the a11y tree while this overlay presents.
            // `.isModal` alone isolates it (sim-verified via `idb ui describe-all`
            // on both apps: every board/digit-pad element drops out of the
            // reported tree, leaving only the hero + CTAs). Also applied to the
            // standalone pushed `.completion` route (macOS) — harmless there since
            // that route has no board sibling to begin with.
            .accessibilityAddTraits(.isModal)
    }

    /// Split from `body` so `.onAppear` sits on the ALWAYS-fully-opaque
    /// content, not on the `.opacity(panelOpacity)`-wrapped result — mirrors
    /// `CompletionScreen.hero`'s structure (per-element opacity inside an
    /// opaque container) and fixes an offline-renderer regression where
    /// `.onAppear` never fired when attached after `.opacity(0)`
    /// (sim/snapshot-confirmed: `MinesweeperBoardTerminalOverlaySnapshotTests`).
    private var content: some View {
        ZStack {
            accentGlow
            glassPanel
            // Section gap (#762 PR1 two-tier spacing contract) — structural,
            // fixed rhythm between the result card and its CTA group;
            // reinforced by the `.dynamicTypeSize` cap just below, which
            // exists specifically so this overlay can't grow past the
            // screen.
            VStack(spacing: theme.spacing.large) {
                card()
                    .environment(\.completionVariant, variant)
                ctas
            }
            .frame(maxWidth: 480)
            .padding(.horizontal, theme.spacing.large)
            // Cap Dynamic Type so the (non-scrolling) group can't grow past the
            // screen — mirrors the board status bar's cap. Extreme-AX overflow
            // scroll is a possible follow-up; the cap keeps it on-screen.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .onAppear { panelRevealed = true }
    }

    // MARK: - Panel rise (M10)

    private var panelAnimation: Animation? {
        switch motionPlan.panelRise {
        case .rise(let duration, _): .easeOut(duration: duration)
        case .fadeInPlace(let duration): .easeOut(duration: duration)
        case .none: nil
        }
    }

    private var panelOffsetY: CGFloat {
        guard case .rise = motionPlan.panelRise else { return 0 }
        return isPanelRevealed ? 0 : 32
    }

    private var panelOpacity: Double {
        switch motionPlan.panelRise {
        case .rise, .fadeInPlace: isPanelRevealed ? 1 : 0
        case .none: 1
        }
    }

    // MARK: - Glass surface (G6, §4.4/§4.5)

    /// Full-bleed, `.regular` glass (§4.5 — never `clear`; this cluster is
    /// full of text: timer-adjacent hero stats, CTA labels). The surface
    /// itself carries NO tint (§4.7) — color comes only from `accentGlow`
    /// painted behind it.
    private var glassPanel: some View {
        GlassEffectContainer {
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: Rectangle())
        }
        .ignoresSafeArea()
    }

    /// M1 (accent seep) + M10's accompanying glow, painted BEHIND the glass
    /// so the glass naturally picks up the tint (§3.5, `color.md:68`). Only
    /// renders when the panel actually rises (`liveSolve`) — `review` shows
    /// no glow, matching its "no ritual" contract.
    @ViewBuilder
    private var accentGlow: some View {
        if case .rise(_, let glowDuration) = motionPlan.panelRise {
            // Subtle by design — this paints BEHIND the glass so the glass
            // itself picks up the tint (§3.5); it must not overpower the
            // CTA text sitting on top of the glass.
            RadialGradient(
                colors: [glowTint.opacity(isPanelRevealed ? 0.16 : 0), .clear],
                center: .bottom,
                startRadius: 0,
                endRadius: 260
            )
            .ignoresSafeArea()
            .animation(.easeOut(duration: glowDuration), value: isPanelRevealed)
        }
    }

    private var glowTint: Color {
        outcomeKind == .success ? theme.accent.celebratory.resolved : theme.status.error.resolved
    }

    // MARK: - CTA hierarchy (§3.5's 4-row table)

    // spacing-exempt: 12pt (gap between full-width CTA buttons) predates
    // the 5-tier `SpacingTokens` scale — no matching tier to route
    // through without snapping to a neighbor and changing this
    // overlay's existing layout/snapshot. Tracked as a follow-up once
    // the token-scale gap gets an owner decision (#762).
    @ViewBuilder
    private var ctas: some View {
        VStack(spacing: 12) {
            switch context {
            case .dailyMoreToday(let nextDifficultyLabel, let onNext):
                primaryButton(action: onNext) {
                    // Two independently-localized segments, matching the
                    // repo's established difficulty-label composition
                    // (PracticeHubView.swift) rather than a %@ format string.
                    Text("\(Text("Next:", bundle: .main)) \(Text(nextDifficultyLabel, bundle: .main))")
                }
                secondaryButton(action: onClose, titleKey: "Done", identifier: "game.completion.close")
            case .dailyAllDone:
                // The ONE value-toned CTA in the flow (§3.5) — its action IS
                // Close; there is nothing else to do from this screen. No
                // secondary scaffold button: the reminder opt-in (when
                // unauthorized) is the existing card-level footer.
                primaryButton(action: onClose, identifier: "game.completion.close") {
                    Text("See you tomorrow", bundle: .main)
                }
            case .practice(let onPlayAgain):
                if let onPlayAgain {
                    primaryButton(action: onPlayAgain) {
                        Text("Play Again", bundle: .main)
                    }
                    secondaryButton(action: onClose, titleKey: "Close", identifier: "game.completion.close")
                } else {
                    primaryButton(action: onClose, identifier: "game.completion.close") {
                        Text("Close", bundle: .main)
                    }
                }
            case .loss(let onTryAgain):
                if let onTryAgain {
                    primaryButton(action: onTryAgain) {
                        Text("Try Again", bundle: .main)
                    }
                    secondaryButton(action: onClose, titleKey: "Close", identifier: "game.completion.close")
                } else {
                    primaryButton(action: onClose, identifier: "game.completion.close") {
                        Text("Close", bundle: .main)
                    }
                }
            }
        }
        .padding(.horizontal, theme.spacing.small)
    }

    /// The ONE tinted control on this glass sheet (§4.7: "同一片玻璃最多一個著色控制項").
    private func primaryButton(
        action: @escaping () -> Void,
        identifier: String? = nil,
        @ViewBuilder label: () -> some View
    ) -> some View {
        Button(action: action) {
            // #797: `.foregroundStyle` MUST sit on the label content here,
            // not chained after `.buttonStyle` below — see the historical
            // rationale this pattern was established under (originally in
            // this file, #786/#797).
            label()
                .frame(maxWidth: .infinity)
                .foregroundStyle(theme.surface.primary.resolved)
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.accent.primary.resolved)
        .controlSize(.large)
        .modifier(OptionalAccessibilityIdentifier(identifier: identifier))
    }

    /// Never tinted (§4.7 — the primary above is the sheet's one colored
    /// control); plain `.bordered`.
    private func secondaryButton(
        action: @escaping () -> Void,
        titleKey: LocalizedStringKey,
        identifier: String? = nil
    ) -> some View {
        Button(action: action) {
            Text(titleKey, bundle: .main)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .modifier(OptionalAccessibilityIdentifier(identifier: identifier))
    }
}

private struct OptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}
