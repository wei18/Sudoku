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
internal import GameShellUI
internal import MinesweeperEngine

public struct MinesweeperDailyHubView: View {
    @Bindable private var viewModel: MinesweeperDailyHubViewModel
    @Environment(\.theme) private var theme

    public init(viewModel: MinesweeperDailyHubViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        DailyHubShellView(
            title: "Daily",
            backgroundColor: theme.surface.background.resolved,
            state: liftedState,
            card: { card in MinesweeperDailyCardView(card: card) },
            failure: { reason in
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(theme.status.warning.resolved)
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(theme.text.secondary.resolved)
                }
            },
            onItemTap: { card in viewModel.cardTapped(card) }
        )
        .task { await viewModel.bootstrap() }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
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
                } else {
                    Text("—")
                        .font(.callout)
                        .foregroundStyle(theme.text.tertiary.resolved)
                }
            }
            Text(boardSummary(card.difficulty))
                .font(.caption)
                .foregroundStyle(theme.text.secondary.resolved)
                .accessibilityHidden(true)
        }
        .padding(16)
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

    private func boardSummary(_ level: Difficulty) -> String {
        "\(level.rows) × \(level.columns) · \(level.mineCount) mines"
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
