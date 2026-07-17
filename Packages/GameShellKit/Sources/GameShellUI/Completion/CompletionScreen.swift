// CompletionScreen — the shared game-over / completion view BODY (#418).
//
// Extracted from SudokuUI.CompletionView + MinesweeperUI.MinesweeperCompletionView,
// whose hero cards were near-verbatim mirrors. This is the shared *body*; each
// app keeps its OWN presentation:
//   - Sudoku renders it inside its pushed `.completion` AppRoute.
//   - Minesweeper renders it inside its inline full-cover board `.overlay` (#388).
//
// Everything app-specific is INJECTED:
//   - the result outcome (icon / label / tint / a11y) — solve-only vs win/loss,
//   - the action buttons (primary/secondary CTAs) as injected closures,
//   - all app-divergent strings as `LocalizedStringKey` resolved from each app's
//     own `Localizable.xcstrings` (Bundle.main), exactly as the prior literals did.
//
// #698: the leaderboard-zone 5-state fetch/present machine (the leaderboard-
// state enum, the leaderboard-row value type, and the `onSignIn`/
// `onRetryLeaderboard`/`loadedAccessory` params) was deleted here — both apps
// had hardcoded `state: .hidden` since v2.6 (SDD-003 Epic 4) and no production
// call site ever mapped a fetched slice into a rendered row, so the machinery
// never rendered. The body is now hero + actions + footer only.
//
// Themed via `@Environment(\.theme)` — the host injects its concrete palette.

public import SwiftUI

// MARK: - Outcome

/// The result hero's appearance. Sudoku is solve-only (`.success`); Minesweeper
/// injects `.success` on a win and `.failure` on a loss. Carries its own a11y
/// label so each app phrases it ("Solved in …" / "Boom. Lasted …").
public struct CompletionOutcome: Equatable {
    public enum Kind: Equatable { case success, failure }

    public var kind: Kind
    /// SF Symbol for the hero glyph (e.g. `checkmark.circle.fill`, `burst.fill`).
    public var systemImage: String
    /// Large-title result label ("Solved!", "You won", "Boom").
    public var title: LocalizedStringKey
    /// Full a11y label for the hero ("Solved in 4:11", "Boom. Lasted 1:05").
    public var accessibilityLabel: Text

    public init(
        kind: Kind,
        systemImage: String,
        title: LocalizedStringKey,
        accessibilityLabel: Text
    ) {
        self.kind = kind
        self.systemImage = systemImage
        self.title = title
        self.accessibilityLabel = accessibilityLabel
    }
}

// MARK: - Screen

public struct CompletionScreen: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.completionHeroSkipsReveal) private var skipsReveal

    /// design-system.md §Motion "CompletionView hero stat reveal" (350 ms
    /// fade + 8 pt rise, stagger 60 ms / reduced motion: instant fade).
    /// Starts `false` and flips true on appear so the reveal plays once per
    /// presentation rather than replaying on every re-render.
    @State private var heroRevealed = false

    private let outcome: CompletionOutcome
    /// Hero subtitle time ("4:11"). `nil` OMITS the time row entirely (symbol +
    /// title only) — used by MS's re-opened solved-daily route, which has no
    /// stored elapsed (#284/#386); the real ranked time still shows in the
    /// leaderboard slice. Every has-time caller (Sudoku, MS in-game overlay)
    /// passes a real label, so their layout is unchanged.
    private let elapsedLabel: String?
    /// Number of mistakes made during the game. `nil` for games that have no
    /// mistake concept (Minesweeper) — the row is OMITTED entirely when nil.
    /// Sudoku passes `GameViewModel.mistakeCount`; the popup renders it below
    /// the time row in the hero card (SDD-003 Epic 4).
    private let mistakeCount: Int?
    /// Action buttons injected by the host app. SDD-003 Epic 4: each app now
    /// injects ONLY a Close button here (Retry / New Game / Leaderboard removed
    /// at the injection sites). Renders after the hero.
    private let actions: AnyView
    /// Optional extra content appended after the actions (Sudoku's reminder
    /// affordance). `nil` for apps that don't use it.
    private let footer: AnyView?

    // Hero card padding (#762 PR1 two-tier spacing contract) — content
    // tier, wraps the icon/title/time/mistakes stack, scales with Dynamic
    // Type.
    @ScaledSpacing(.large) private var heroPadding

    public init(
        outcome: CompletionOutcome,
        elapsedLabel: String?,
        mistakeCount: Int? = nil,
        @ViewBuilder actions: () -> some View = { EmptyView() },
        @ViewBuilder footer: () -> some View = { EmptyView() }
    ) {
        self.outcome = outcome
        self.elapsedLabel = elapsedLabel
        self.mistakeCount = mistakeCount
        self.actions = AnyView(actions())
        let builtFooter = footer()
        self.footer = builtFooter is EmptyView ? nil : AnyView(builtFooter)
    }

    public var body: some View {
        // Intrinsic-height card content. The host wrapper
        // (`CompletionOverlayScaffold`) owns the themed background, vertical
        // centring of the whole {card + CTAs} group, and scroll-on-overflow —
        // so this view just lays out its content at its natural height and lets
        // the wrapper place it. `.padding` + max-width cap keep the card inset.
        // Section gap (#762 PR1 two-tier spacing contract) — structural,
        // fixed rhythm between hero/actions/footer.
        VStack(spacing: theme.spacing.large) {
            hero
            actions
            if let footer { footer }
        }
        // spacing-exempt: 20pt (card padding) predates the 5-tier
        // `SpacingTokens` scale — no matching tier to route through
        // without snapping to a neighbor and changing this card's
        // existing layout/snapshot. Tracked as a follow-up once the
        // token-scale gap gets an owner decision (#762).
        .padding(20)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Hero

    /// `heroRevealed` OR the test/offline-renderer escape hatch below — see
    /// `completionHeroSkipsReveal`.
    private var isHeroRevealed: Bool { heroRevealed || skipsReveal }

    private var hero: some View {
        // spacing-exempt: 10pt (icon/title/time/mistakes stack gap)
        // predates the 5-tier `SpacingTokens` scale — no matching tier to
        // route through without snapping to a neighbor and changing this
        // hero's existing layout/snapshot. Tracked as a follow-up once the
        // token-scale gap gets an owner decision (#762).
        VStack(spacing: 10) {
            Image(systemName: outcome.systemImage)
                .font(.system(size: 56))
                .foregroundStyle(heroTint)
                .heroReveal(isHeroRevealed, index: 0, reduceMotion: reduceMotion)
            Text(outcome.title)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(theme.text.primary.resolved)
                .heroReveal(isHeroRevealed, index: 1, reduceMotion: reduceMotion)
            // Omit the time row entirely when there's no elapsed (MS re-opened
            // solved-daily, #386) — no placeholder/empty row. Has-time callers
            // render the identical `Text` as before, so snapshots are unchanged.
            if let elapsedLabel {
                Text(elapsedLabel)
                    .font(.title3)
                    .foregroundStyle(theme.text.secondary.resolved)
                    .monospacedDigit()
                    .heroReveal(isHeroRevealed, index: 2, reduceMotion: reduceMotion)
            }
            // Mistakes row — only shown when the game tracks mistakes (Sudoku).
            // Minesweeper passes `nil` and the row is fully absent (no height,
            // no empty space). Key follows the repo's literal-as-key convention
            // ("Mistakes: %lld" ×7 locales in the app catalogs, resolved via
            // Bundle.main at runtime — readable English in snapshots). (Epic 4)
            if let mistakeCount {
                // spacing-exempt: 6pt (icon-to-text gap) predates the
                // 5-tier `SpacingTokens` scale — same rationale as the hero
                // stack above (#762).
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(mistakeCount == 0 ? theme.status.success.resolved : theme.status.error.resolved)
                    Text("Mistakes: \(mistakeCount)")
                        .font(.subheadline)
                        .foregroundStyle(theme.text.secondary.resolved)
                        .monospacedDigit()
                }
                .heroReveal(isHeroRevealed, index: 3, reduceMotion: reduceMotion)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(heroPadding)
        .background(theme.surface.elevated.resolved, in: RoundedRectangle(cornerRadius: 20))
        // #846: card blended into the near-white/warm-paper page background
        // (measured light-mode contrast ratio ~1.06:1 — no darker flat
        // "elevated" token exists in this theme system to swap to). Border
        // is the load-bearing a11y cue (survives Reduce Transparency /
        // Increase Contrast); shadow roughly doubled for a real lifted-card
        // read. Zero new color tokens — reuses `theme.text.tertiary`.
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(theme.text.tertiary.resolved.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 16, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(outcome.accessibilityLabel)
        // #510 Phase 3: stable, non-localized anchor so the host-driven
        // XCUITest E2E flow can assert "completion overlay appeared" after the
        // winning move, in any locale. Both apps render CompletionScreen, so
        // this single identifier serves both (mirror principle).
        .accessibilityIdentifier("game.completion.hero")
        // Reveal plays once per presentation, not on every body re-evaluation
        // (e.g. a theme/locale environment change while the screen is up).
        // NOTE: `.onAppear` does not fire on an off-screen `NSHostingView`
        // that's never added to a real window (confirmed empirically) — the
        // snapshot-test / ASC-screenshot harnesses render exactly that way,
        // so they rely on `completionHeroSkipsReveal` below rather than this
        // callback ever running.
        .onAppear { heroRevealed = true }
    }

    private var heroTint: Color {
        switch outcome.kind {
        case .success: theme.status.success.resolved
        case .failure: theme.status.error.resolved
        }
    }
}

// MARK: - Hero reveal

private extension View {
    /// design-system.md §Motion "CompletionView hero stat reveal": 350 ms
    /// fade + 8 pt rise, staggered 60 ms per element by `index`; reduced
    /// motion drops straight to the revealed state (instant fade, no rise).
    func heroReveal(_ revealed: Bool, index: Int, reduceMotion: Bool) -> some View {
        opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 8)
            .animation(
                MotionGate.animation(
                    .easeOut(duration: 0.35).delay(Double(index) * 0.06),
                    reduceMotion: reduceMotion
                ),
                value: revealed
            )
    }
}

// MARK: - Offline-renderer escape hatch

private struct CompletionHeroSkipsRevealKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// Test/offline-renderer-only override (mirrors `BannerSlotView`'s
    /// `bannerSlotLoadingPreview`, #732): `CompletionScreen`'s hero-reveal
    /// animation is driven by `.onAppear`, which never fires on an
    /// `NSHostingView` that isn't attached to a real window — exactly how
    /// the snapshot-test harness and the ASC screenshot emitter render a
    /// view for a single synchronous capture. Without this seam those
    /// captures show a permanently blank hero (the pre-reveal opacity-0
    /// state), not a "needs a longer wait" issue — waiting does not help,
    /// since the callback that would flip the state never runs at all.
    /// `false` (default) leaves the live app's real entrance animation
    /// untouched; only offline renderers set this via
    /// `.environment(\.completionHeroSkipsReveal, true)` from OUTSIDE
    /// `CompletionScreen`'s own view tree.
    var completionHeroSkipsReveal: Bool {
        get { self[CompletionHeroSkipsRevealKey.self] }
        set { self[CompletionHeroSkipsRevealKey.self] = newValue }
    }
}
