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
        VStack(spacing: 24) {
            hero
            actions
            if let footer { footer }
        }
        .padding(20)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 10) {
            Image(systemName: outcome.systemImage)
                .font(.system(size: 56))
                .foregroundStyle(heroTint)
            Text(outcome.title)
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(theme.text.primary.resolved)
            // Omit the time row entirely when there's no elapsed (MS re-opened
            // solved-daily, #386) — no placeholder/empty row. Has-time callers
            // render the identical `Text` as before, so snapshots are unchanged.
            if let elapsedLabel {
                Text(elapsedLabel)
                    .font(.title3)
                    .foregroundStyle(theme.text.secondary.resolved)
                    .monospacedDigit()
            }
            // Mistakes row — only shown when the game tracks mistakes (Sudoku).
            // Minesweeper passes `nil` and the row is fully absent (no height,
            // no empty space). Key follows the repo's literal-as-key convention
            // ("Mistakes: %lld" ×7 locales in the app catalogs, resolved via
            // Bundle.main at runtime — readable English in snapshots). (Epic 4)
            if let mistakeCount {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(mistakeCount == 0 ? theme.status.success.resolved : theme.status.error.resolved)
                    Text("Mistakes: \(mistakeCount)")
                        .font(.subheadline)
                        .foregroundStyle(theme.text.secondary.resolved)
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(outcome.accessibilityLabel)
        // #510 Phase 3: stable, non-localized anchor so the host-driven
        // XCUITest E2E flow can assert "completion overlay appeared" after the
        // winning move, in any locale. Both apps render CompletionScreen, so
        // this single identifier serves both (mirror principle).
        .accessibilityIdentifier("game.completion.hero")
    }

    private var heroTint: Color {
        switch outcome.kind {
        case .success: theme.status.success.resolved
        case .failure: theme.status.error.resolved
        }
    }
}
