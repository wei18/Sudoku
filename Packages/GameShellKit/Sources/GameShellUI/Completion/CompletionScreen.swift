// CompletionScreen — the shared game-over / completion view BODY (#418).
//
// Extracted from SudokuUI.CompletionView + MinesweeperUI.MinesweeperCompletionView,
// whose hero card, leaderboard slice section, and loading / unauthenticated /
// not-ranked / failed state blocks were near-verbatim mirrors. This is the shared
// *body*; each app keeps its OWN presentation:
//   - Sudoku renders it inside its pushed `.completion` AppRoute.
//   - Minesweeper renders it inside its inline full-cover board `.overlay` (#388).
//
// Everything app-specific is INJECTED:
//   - the result outcome (icon / label / tint / a11y) — solve-only vs win/loss,
//   - the leaderboard rows as a PLAIN value type (`CompletionLeaderboardRow`) so
//     GameShellUI never imports GameCenterClient / GameKit (leaderboard + GC
//     coupling stays in each app's Kit; this shell stays game-agnostic),
//   - the action buttons (primary/secondary CTAs) as injected closures,
//   - all app-divergent strings as `LocalizedStringKey` resolved from each app's
//     own `Localizable.xcstrings` (Bundle.main), exactly as the prior literals did.
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

// MARK: - Leaderboard row (GameCenter-free value type)

/// A single leaderboard row, pre-formatted by the app. Deliberately NOT
/// `GameCenterClient.LeaderboardEntry` — the shell must not import GameCenterClient,
/// so apps map their fetched slice into these plain values at the call site.
public struct CompletionLeaderboardRow: Identifiable, Equatable {
    public var rank: Int
    public var displayName: String
    /// Pre-formatted score label (e.g. "4:11"). The shell renders it verbatim.
    public var score: String

    public var id: Int { rank }

    public init(rank: Int, displayName: String, score: String) {
        self.rank = rank
        self.displayName = displayName
        self.score = score
    }
}

// MARK: - State

/// The shared content state both apps' completion surfaces map onto. Unifies
/// Sudoku's set (which has `.noLeaderboard`, #383) with Minesweeper's — MS now
/// gets the shared `.noLeaderboard` too even though it doesn't drive it today.
public enum CompletionScreenState: Equatable {
    case loading
    case loaded([CompletionLeaderboardRow])
    case unauthenticated
    /// No associated leaderboard (e.g. Sudoku Practice solves, #383) — neutral
    /// "not ranked" copy, no sign-in CTA.
    case noLeaderboard
    case failed
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
    private let state: CompletionScreenState
    /// Optional sign-in CTA shown under the `.unauthenticated` copy (Sudoku wires
    /// it; Minesweeper passes `nil` → copy only, matching its prior surface).
    private let onSignIn: (() -> Void)?
    /// Retry from the `.failed` block (re-fetch the leaderboard slice).
    private let onRetryLeaderboard: () -> Void
    /// Accessory rendered INSIDE the `.loaded` case as a sibling in the outer
    /// `VStack(spacing: 24)`, immediately after the leaderboard section (so 24pt
    /// below it — same as the parent group spacing, matching Sudoku's prior
    /// layout exactly; do NOT "tighten" this or the baseline shifts). Sudoku's
    /// "View full leaderboard" CTA sits here. MS leaves it empty (its CTA lives
    /// in the always-on `actions` stack instead).
    private let loadedAccessory: AnyView
    /// Action buttons injected by the host app. SDD-003 Epic 4: each app now
    /// injects ONLY a Close button here (Retry / New Game / Leaderboard removed
    /// at the injection sites). Renders after the state content.
    private let actions: AnyView
    /// Optional extra content appended after the actions (Sudoku's reminder
    /// affordance). `nil` for apps that don't use it.
    private let footer: AnyView?

    public init(
        outcome: CompletionOutcome,
        elapsedLabel: String?,
        mistakeCount: Int? = nil,
        state: CompletionScreenState,
        onSignIn: (() -> Void)? = nil,
        onRetryLeaderboard: @escaping () -> Void,
        @ViewBuilder loadedAccessory: () -> some View = { EmptyView() },
        @ViewBuilder actions: () -> some View = { EmptyView() },
        @ViewBuilder footer: () -> some View = { EmptyView() }
    ) {
        self.outcome = outcome
        self.elapsedLabel = elapsedLabel
        self.mistakeCount = mistakeCount
        self.state = state
        self.onSignIn = onSignIn
        self.onRetryLeaderboard = onRetryLeaderboard
        self.loadedAccessory = AnyView(loadedAccessory())
        self.actions = AnyView(actions())
        let builtFooter = footer()
        self.footer = builtFooter is EmptyView ? nil : AnyView(builtFooter)
    }

    public var body: some View {
        // SDD-003 Epic 4: popup/card shape. The host app still owns the
        // presentation (Sudoku: pushed route; MS: full-board overlay) but
        // CompletionScreen itself now renders as a centered card rather than a
        // bare full-screen fill. `.padding` + max-width cap give the card its
        // inset appearance; the host's background bleeds around it.
        ScrollView {
            VStack(spacing: 24) {
                hero
                content
                actions
                if let footer { footer }
            }
            .padding(20)
            .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.surface.background.resolved)
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
            // no empty space). The label uses the key "completion.mistakes"
            // (static label, 7-locale) concatenated with the count so no
            // format-string substitution is needed in xcstrings. (SDD-003 Epic 4)
            if let mistakeCount {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(mistakeCount == 0 ? theme.status.success.resolved : theme.status.error.resolved)
                    Text("completion.mistakes")
                        .font(.subheadline)
                        .foregroundStyle(theme.text.secondary.resolved)
                    + Text(verbatim: ": \(mistakeCount)")
                        .font(.subheadline)
                        .foregroundStyle(theme.text.secondary.resolved)
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(outcome.accessibilityLabel)
    }

    private var heroTint: Color {
        switch outcome.kind {
        case .success: theme.status.success.resolved
        case .failure: theme.status.error.resolved
        }
    }

    // MARK: - State content

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, minHeight: 120)
        case .loaded(let rows):
            leaderboardSection(rows)
            loadedAccessory
        case .unauthenticated:
            unauthenticatedBlock
        case .noLeaderboard:
            noLeaderboardBlock
        case .failed:
            failedBlock
        }
    }

    private func leaderboardSection(_ rows: [CompletionLeaderboardRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Leaderboard")
                .font(.headline)
                .foregroundStyle(theme.text.primary.resolved)
            VStack(spacing: 4) {
                ForEach(rows) { row in
                    HStack {
                        Text("\(row.rank).")
                            .monospacedDigit()
                            .foregroundStyle(theme.text.secondary.resolved)
                            .frame(width: 32, alignment: .trailing)
                        Text(row.displayName)
                            .foregroundStyle(theme.text.primary.resolved)
                        Spacer()
                        Text(row.score)
                            .monospacedDigit()
                            .foregroundStyle(theme.text.primary.resolved)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                }
            }
        }
    }

    private var unauthenticatedBlock: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 36))
                .foregroundStyle(theme.text.secondary.resolved)
            Text("Sign in to Game Center to compare with others.")
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.text.primary.resolved)
            if let onSignIn {
                Button("Sign in", action: onSignIn)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        }
        .padding(.top, 16)
    }

    // Practice solves have no leaderboard (#383). Neutral, terminal copy — no
    // sign-in CTA (nothing to sign in for) and no dead button.
    private var noLeaderboardBlock: some View {
        VStack(spacing: 12) {
            Image(systemName: "dial.medium")
                .font(.system(size: 36))
                .foregroundStyle(theme.text.secondary.resolved)
            Text("Practice puzzles aren't ranked.")
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.text.primary.resolved)
        }
        .padding(.top, 16)
    }

    private var failedBlock: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(theme.status.warning.resolved)
            Text("Couldn't load leaderboard.")
                .foregroundStyle(theme.text.primary.resolved)
            Button(action: onRetryLeaderboard) {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 16)
    }
}
