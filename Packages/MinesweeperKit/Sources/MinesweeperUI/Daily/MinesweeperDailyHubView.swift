// MinesweeperDailyHubView — date-seeded Daily hub (#290).
//
// Real daily content, replacing the PR U12 placeholder. Mirrors Sudoku's
// `DailyHubView`: produces the game-specific `MinesweeperDailyCard` items +
// MS theme colors and hands them to the generic `GameShellUI.DailyHubShellView`.
// `.task { bootstrap() }` stays on the caller (shells own no side-effect
// modifiers — X4 / SettingsShellView precedent).
//
// The daily trio = one date-seeded board per difficulty (beginner /
// intermediate / expert), the same three boards for everyone on a given UTC
// day, rolling over at UTC midnight. Tapping a card pushes `.board(...)` with
// the daily seed. Completed cards show a checkmark (driven off
// `PersistenceProtocol.fetchCompletedDailyIds`; parity-only until MS daily
// save-flow lands).

public import SwiftUI
internal import GameAppKit
internal import GameShellUI
internal import MinesweeperEngine

public struct MinesweeperDailyHubView<Banner: View>: View {
    // #536: @State (first-value-wins) so a re-render that mints a fresh idle
    // VM from the factory does not replace the bootstrapped instance. Mirrors
    // the Sudoku fix in DailyHubView — both share the same @Bindable bug class.
    @State private var viewModel: MinesweeperDailyHubViewModel
    @Environment(\.theme) private var theme
    // #761: `.onAppear` does NOT re-fire when the board's fullScreenCover
    // dismisses (sim-verified — no re-fire on the real Close → Leave flow;
    // the only re-fire is a transient GameBoardRedirect push-pop at board
    // OPEN, which is useless here since completion doesn't exist yet). This
    // hub instead listens to `GameRoot`'s explicit teardown counter, mirroring
    // the `ResumePill` / `refreshResumeCandidate` precedent (#675). Mirrors
    // Sudoku's `DailyHubView`.
    @Environment(\.gameSessionTeardownCount) private var sessionTeardownCount
    private let banner: Banner

    public init(
        viewModel: MinesweeperDailyHubViewModel,
        @ViewBuilder banner: () -> Banner = { EmptyView() }
    ) {
        _viewModel = State(wrappedValue: viewModel)
        self.banner = banner()
    }

    public var body: some View {
        // #774: the week strip sits above the trio, outside
        // `DailyHubShellView` (GameShellKit stays untouched — see
        // `MinesweeperDailyStripView`'s header comment on the "no shared
        // widget" scope note). It renders regardless of the shell's own
        // idle/loading/loaded state — the strip has its own independent
        // fetch. Mirrors Sudoku's `DailyHubView`.
        VStack(spacing: 0) {
            MinesweeperDailyStripView(snapshot: viewModel.weekStrip, onDayTap: { day in viewModel.dayTapped(day) })
                .padding(.horizontal, theme.spacing.medium)
                .padding(.top, theme.spacing.medium)
            dailyHubShell
        }
        .background(theme.surface.background.resolved)
        .task { await viewModel.bootstrap() }
        // #761: driven by `GameRoot`'s explicit teardown counter (not
        // `.onAppear` — see the property doc above for why that doesn't
        // work). `refresh()`'s own `.loaded`-state guard still protects
        // against a spurious fetch before `bootstrap()` has landed. Also
        // refreshes `viewModel.weekStrip` (#774) — same `refresh()` call,
        // no new trigger. Mirrors Sudoku's `DailyHubView`.
        .onChange(of: sessionTeardownCount) { _, _ in Task { await viewModel.refresh() } }
        // #826: mirrors Sudoku's `DailyHubView` picker — a past day with >1
        // completed difficulty presents this instead of opening directly
        // (owner adjudication 2026-07-16).
        .confirmationDialog(
            "Difficulty",
            isPresented: Binding(
                get: { viewModel.reviewPickerChoices != nil },
                set: { isPresented in
                    if !isPresented { viewModel.dismissReviewPicker() }
                }
            ),
            presenting: viewModel.reviewPickerChoices
        ) { choices in
            ForEach(choices) { choice in
                // `.rawValue.capitalized` maps beginner/intermediate/expert →
                // the existing "Beginner"/"Intermediate"/"Expert" L10n keys —
                // byte-mirrors Sudoku's picker rows (whose capitalized
                // rawValues likewise hit its "Easy"/"Medium"/"Hard" keys).
                Button(LocalizedStringKey(choice.difficulty.rawValue.capitalized)) {
                    viewModel.reviewChoiceSelected(choice)
                }
            }
        }
    }

    private var dailyHubShell: some View {
        DailyHubShellView(
            title: "Daily",
            backgroundColor: theme.surface.background.resolved,
            state: liftedState,
            card: { card in MinesweeperDailyCardView(card: card) },
            failure: { reason in
                // spacing-exempt: 12pt (icon/text stack gap) predates the
                // 5-tier `SpacingTokens` scale — no matching tier without
                // snapping and changing this screen's existing
                // layout/snapshot (#762 PR3).
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(theme.status.warning.resolved)
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(theme.text.secondary.resolved)
                }
            },
            onItemTap: { card in viewModel.cardTapped(card) },
            banner: { banner }
        )
    }

    /// Translates the MS daily state into the generic shell input. MS has no
    /// `.exhausted` / `.failed` path (generation is pure + non-throwing), so
    /// only idle / loading / loaded are reachable.
    private var liftedState: HubLoadState<MinesweeperDailyCard> {
        switch viewModel.state {
        case .idle: return .idle
        case .loading: return .loading
        case .loaded(let cards): return .loaded(cards)
        }
    }
}

private struct MinesweeperDailyCardView: View {
    let card: MinesweeperDailyCard
    @Environment(\.theme) private var theme
    // #762 PR3: content tier (two-tier contract, design-system.md §Spacing
    // scale). Both wrap the card's own header row / caption stack — 8
    // matches `SpacingTokens.small`; shared since both call sites use the
    // same tier.
    @ScaledSpacing(.small) private var contentGap
    // Card outer padding — mirrors GameShellUI's `HomeModeCard.cardPadding`
    // precedent (PR1): 16 matches `SpacingTokens.medium`.
    @ScaledSpacing(.medium) private var cardPadding

    var body: some View {
        VStack(alignment: .leading, spacing: contentGap) {
            HStack(spacing: contentGap) {
                Circle()
                    .fill(difficultyTint)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(displayName(card.difficulty))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(difficultyTint)
                Spacer()
                if card.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.status.success.resolved)
                        .font(.callout)
                        .accessibilityLabel("Completed")
                } else if card.isFailed {
                    // Epic 8 (SDD-003): third state — mine hit on this daily.
                    // "Replay" affordance is communicated by the tap action.
                    Label {
                        Text("Failed")
                    } icon: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .font(.callout)
                    .foregroundStyle(theme.status.warning.resolved)
                    .accessibilityLabel("Failed")
                } else {
                    // #516: a "tap to play" chevron reads clearer than the bare
                    // em-dash, which looked like a placeholder rather than an
                    // unplayed state. Decorative — the card's combined a11y
                    // element already conveys the difficulty + button trait.
                    Image(systemName: "chevron.right")
                        .font(.callout)
                        .foregroundStyle(theme.text.tertiary.resolved)
                        .accessibilityHidden(true)
                }
            }
            boardSummary(card.difficulty)
                .font(.caption)
                .foregroundStyle(theme.text.secondary.resolved)
                .accessibilityHidden(true)
        }
        .padding(cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        // `.contentShape(Rectangle())` BEFORE `.glassEffect(...)` so the whole
        // card frame (incl. padding) is tap-hittable on macOS — mirrors
        // Sudoku's DailyPuzzleCard / HomeView card ordering (issue #15 / #197).
        .contentShape(Rectangle())
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// Map `Difficulty` to a `difficulty.*` theme token. Exhaustive — adding a
    /// case forces this to update (mirrors Sudoku's `difficultyTint`).
    private var difficultyTint: Color {
        switch card.difficulty {
        case .beginner: return theme.difficulty.easy.resolved
        case .intermediate: return theme.difficulty.medium.resolved
        case .expert: return theme.difficulty.hard.resolved
        }
    }

    private func displayName(_ level: Difficulty) -> LocalizedStringKey {
        switch level {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .expert: return "Expert"
        }
    }

    // #595: one localized key `"%lld × %lld · %lld mines"` so "mines" is translated
    // (dimensions + `× / ·` carry through). MS mine counts are always ≥ 10, so a
    // non-plural key is grammatically correct in every locale.
    private func boardSummary(_ level: Difficulty) -> Text {
        Text("\(level.rows) × \(level.columns) · \(level.mineCount) mines")
    }
}

#Preview("MinesweeperDailyHub") {
    NavigationStack {
        MinesweeperDailyHubView(
            viewModel: MinesweeperDailyHubViewModel(path: .constant([]))
        )
    }
    .environment(\.theme, MinesweeperTheme())
}
