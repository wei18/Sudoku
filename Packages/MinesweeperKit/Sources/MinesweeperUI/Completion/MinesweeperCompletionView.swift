// MinesweeperCompletionView — post-game result surface (#292).
//
// Mirror of `SudokuUI.CompletionView`: a result hero + (on a win) a Game Center
// leaderboard slice centred on the local player, with graceful loading /
// unauthenticated / failed states. CTAs:
//   - New Game  → back to root (injected closure).
//   - Retry     → replay the same difficulty (injected closure).
//   - View leaderboard → Apple's native GC dashboard.
//
// Presented as a full-board overlay in place of the old inline `terminalOverlay`
// (see MinesweeperBoardView) — MS's board owns its win/lose state inline and has
// no completion route, so the surface mounts over the board rather than via a
// pushed AppRoute (the difference from Sudoku's route-pushed Completion; spec
// allows "overlay or pushed"). Everything is themed via `\.theme` tokens.

public import SwiftUI
import GameCenterClient

public struct MinesweeperCompletionView: View {
    @Bindable private var viewModel: MinesweeperCompletionViewModel
    @Environment(\.theme) private var theme

    /// New Game → dismiss to root. `nil` in previews / standalone board.
    private let onNewGame: (() -> Void)?
    /// Retry → replay the same difficulty in place.
    private let onRetry: (() -> Void)?

    public init(
        viewModel: MinesweeperCompletionViewModel,
        onNewGame: (() -> Void)? = nil,
        onRetry: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onNewGame = onNewGame
        self.onRetry = onRetry
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                hero
                content
                actions
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.surface.background.resolved)
        .task { await viewModel.bootstrap() }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 10) {
            Image(systemName: viewModel.didWin ? "checkmark.circle.fill" : "burst.fill")
                .font(.system(size: 56))
                .foregroundStyle(
                    viewModel.didWin
                        ? theme.status.success.resolved
                        : theme.status.error.resolved
                )
            Text(viewModel.didWin ? "You won" : "Boom")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(theme.text.primary.resolved)
            Text(elapsedLabel)
                .font(.title3)
                .foregroundStyle(theme.text.secondary.resolved)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            viewModel.didWin
                ? "You won in \(elapsedLabel)"
                : "Boom. Lasted \(elapsedLabel)"
        )
    }

    // MARK: - Leaderboard slice / states

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, minHeight: 120)
        case .loaded(let slice):
            leaderboardSection(slice)
        case .unauthenticated:
            unauthenticatedBlock
        case .failed:
            failedBlock
        }
    }

    private func leaderboardSection(_ slice: LeaderboardSlice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Leaderboard")
                .font(.headline)
                .foregroundStyle(theme.text.primary.resolved)
            VStack(spacing: 4) {
                ForEach(slice.entries, id: \.rank) { entry in
                    HStack {
                        Text("\(entry.rank).")
                            .monospacedDigit()
                            .foregroundStyle(theme.text.secondary.resolved)
                            .frame(width: 32, alignment: .trailing)
                        Text(entry.player.displayName)
                            .foregroundStyle(theme.text.primary.resolved)
                        Spacer()
                        Text(scoreLabel(entry.score))
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
            Button {
                Task { await viewModel.retry() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 16)
    }

    // MARK: - CTAs

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                viewModel.viewLeaderboardTapped()
            } label: {
                Label("View leaderboard", systemImage: "trophy.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            if let onRetry {
                Button {
                    onRetry()
                } label: {
                    Label("Retry", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if let onNewGame {
                Button {
                    onNewGame()
                } label: {
                    Label("New Game", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    // MARK: - Formatting

    private var elapsedLabel: String {
        timeLabel(viewModel.elapsedSeconds)
    }

    private func scoreLabel(_ seconds: Int) -> String {
        timeLabel(seconds)
    }

    private func timeLabel(_ total: Int) -> String {
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
