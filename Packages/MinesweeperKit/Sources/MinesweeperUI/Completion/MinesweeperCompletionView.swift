// MinesweeperCompletionView — Minesweeper's post-game result surface (#292).
// Thin wrapper over the shared `GameShellUI.CompletionScreen` body (#418).
//
// Minesweeper owns its PRESENTATION: this view is mounted as a full-board
// `.overlay` in place of the old inline `terminalOverlay` (see
// MinesweeperBoardView, #388) — MS's board owns its win/lose state inline and
// has no completion route, so the surface mounts over the board rather than via
// a pushed AppRoute (the difference from Sudoku's route-pushed Completion;
// route-pushed MS Completion deferred — #386).
//
// It maps the leaderboard-fetch VM state onto the shared `CompletionScreenState`,
// injects the win/loss hero outcome, and supplies the always-on action stack:
//   - View leaderboard → Apple's native GC dashboard.
//   - Retry            → replay the same difficulty (injected closure).
//   - New Game         → back to root (injected closure).
// The Game Center coupling stays here; the shared shell never imports
// GameCenterClient. Themed via `\.theme` tokens.

public import SwiftUI
import GameCenterClient
import GameShellUI

public struct MinesweeperCompletionView: View {
    @Bindable private var viewModel: MinesweeperCompletionViewModel

    /// New Game → dismiss to root. `nil` in previews / standalone board.
    private let onNewGame: (() -> Void)?
    /// Retry → replay the same difficulty in place.
    private let onRetry: (() -> Void)?
    /// #386: when re-viewing an already-solved daily there is no stored elapsed
    /// (MS has no save-flow, #284). The route-pushed surface passes a placeholder
    /// (e.g. "--:--") so the hero doesn't render a misleading `0:00`; the real
    /// ranked time still appears in the leaderboard slice. `nil` for the live
    /// post-game overlay, which formats the just-played `viewModel.elapsedSeconds`.
    private let elapsedOverride: String?

    public init(
        viewModel: MinesweeperCompletionViewModel,
        onNewGame: (() -> Void)? = nil,
        onRetry: (() -> Void)? = nil,
        elapsedOverride: String? = nil
    ) {
        self.viewModel = viewModel
        self.onNewGame = onNewGame
        self.onRetry = onRetry
        self.elapsedOverride = elapsedOverride
    }

    public var body: some View {
        CompletionScreen(
            outcome: outcome,
            elapsedLabel: elapsedLabel,
            state: screenState,
            onRetryLeaderboard: { Task { await viewModel.retry() } },
            actions: { actions }
        )
        .task { await viewModel.bootstrap() }
    }

    // MARK: - Outcome (win / loss)

    private var outcome: CompletionOutcome {
        if viewModel.didWin {
            CompletionOutcome(
                kind: .success,
                systemImage: "checkmark.circle.fill",
                title: "You won",
                accessibilityLabel: Text("You won in \(elapsedLabel)")
            )
        } else {
            CompletionOutcome(
                kind: .failure,
                systemImage: "burst.fill",
                title: "Boom",
                accessibilityLabel: Text("Boom. Lasted \(elapsedLabel)")
            )
        }
    }

    // MARK: - State mapping

    // MS has no `.noLeaderboard` today; the shared body still handles it.
    private var screenState: CompletionScreenState {
        switch viewModel.state {
        case .loading:
            .loading
        case .loaded(let slice):
            .loaded(slice.entries.map { entry in
                CompletionLeaderboardRow(
                    rank: entry.rank,
                    displayName: entry.player.displayName,
                    score: timeLabel(entry.score)
                )
            })
        case .unauthenticated:
            .unauthenticated
        case .failed:
            .failed
        }
    }

    // MARK: - CTAs (always-on action stack)

    @ViewBuilder
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
        elapsedOverride ?? timeLabel(viewModel.elapsedSeconds)
    }

    private func timeLabel(_ total: Int) -> String {
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
