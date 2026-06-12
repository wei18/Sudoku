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
// injects the win/loss hero outcome, and supplies the action stack.
//
// SDD-003 Epic 4: actions now inject ONLY a Close button (View Leaderboard /
// Retry / New Game removed at this injection site per spec note). `onClose`
// dismisses the overlay (MinesweeperBoardView sets `completionViewModel = nil`).
// Minesweeper has no mistake concept → `mistakeCount: nil` (row absent).
// The Game Center coupling stays here; the shared shell never imports
// GameCenterClient. Themed via `\.theme` tokens.

public import SwiftUI
import GameCenterClient
import GameShellUI

public struct MinesweeperCompletionView: View {
    @Bindable private var viewModel: MinesweeperCompletionViewModel

    /// SDD-003 Epic 4: dismiss the completion overlay. Wired by
    /// MinesweeperBoardView to `completionViewModel = nil`.
    private let onClose: (() -> Void)?
    /// #386: when re-viewing an already-solved daily there is no stored elapsed
    /// (MS has no save-flow, #284), so the hero OMITS the time row entirely (the
    /// player's real ranked time still appears in the leaderboard slice). The
    /// route-pushed re-opened-daily surface passes `false`; the live post-game
    /// overlay leaves it `true` and formats the just-played `elapsedSeconds`.
    private let showsElapsedTime: Bool

    public init(
        viewModel: MinesweeperCompletionViewModel,
        onClose: (() -> Void)? = nil,
        showsElapsedTime: Bool = true
    ) {
        self.viewModel = viewModel
        self.onClose = onClose
        self.showsElapsedTime = showsElapsedTime
    }

    public var body: some View {
        CompletionScreen(
            outcome: outcome,
            elapsedLabel: elapsedLabel,
            mistakeCount: nil,
            // SDD-003 Epic 4: no leaderboard zone in the popup (mirror of
            // Sudoku's CompletionView). VM fetch machinery left unrendered.
            state: .hidden,
            onRetryLeaderboard: {},
            actions: { closeButton }
        )
    }

    // MARK: - Outcome (win / loss)

    private var outcome: CompletionOutcome {
        if viewModel.didWin {
            CompletionOutcome(
                kind: .success,
                systemImage: "checkmark.circle.fill",
                title: "You won",
                // No elapsed → terse "You won" a11y label (re-opened daily, #386).
                accessibilityLabel: elapsedLabel.map { Text("You won in \($0)") }
                    ?? Text("You won")
            )
        } else {
            CompletionOutcome(
                kind: .failure,
                systemImage: "burst.fill",
                title: "Boom",
                accessibilityLabel: elapsedLabel.map { Text("Boom. Lasted \($0)") }
                    ?? Text("Boom")
            )
        }
    }

    // MARK: - CTAs (SDD-003 Epic 4: Close only)

    // View Leaderboard, Retry, and New Game removed at this injection site per
    // the spec note: "移除發生在各 app 的注入點". GC entry-point relocation is an
    // open product question (see section 7 of the impl report / OQ-GC-001).
    @ViewBuilder
    private var closeButton: some View {
        if let onClose {
            Button {
                onClose()
            } label: {
                Text("Close")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Formatting

    /// Hero subtitle. `nil` when there's no stored elapsed (re-opened solved
    /// daily, #386) so the shared body omits the time row entirely.
    private var elapsedLabel: String? {
        showsElapsedTime ? timeLabel(viewModel.elapsedSeconds) : nil
    }

    private func timeLabel(_ total: Int) -> String {
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
