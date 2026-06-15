// Game2048CompletionView — Tiles2048 post-game result surface.
// Thin wrapper over the shared `GameShellUI.CompletionScreen`.
//
// OQ-004-3 binding:
//   - outcome: "Game Over" hero (no win/lose — stuck = end of run)
//   - score + move count shown; reachedTarget badge if applicable
//   - elapsedLabel: formatted elapsed from the session
//   - state: .hidden (no leaderboard zone in the popup — AD-003 no banner)
//   - CTA: Close only (no Retry — run is over); onClose dismisses overlay
//
// Mounted as a full-board `.overlay` in `Game2048BoardView` when stuck,
// exactly as MinesweeperCompletionView is mounted. The board VM calls
// `onClose` to nil out the completion surface binding.
//
// No banner inside the popup (AD-003).

public import SwiftUI
internal import GameShellUI

public struct Game2048CompletionView: View {
    @Bindable private var viewModel: Game2048CompletionViewModel

    /// Dismiss the completion overlay. Wired by Game2048BoardView to nil
    /// out its `completionViewModel` binding.
    private let onClose: (() -> Void)?

    public init(
        viewModel: Game2048CompletionViewModel,
        onClose: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onClose = onClose
    }

    public var body: some View {
        CompletionScreen(
            outcome: outcome,
            elapsedLabel: elapsedLabel,
            mistakeCount: nil,
            // OQ-004-3: no leaderboard zone in the completion popup.
            state: .hidden,
            onRetryLeaderboard: {},
            actions: { closeButton }
        )
    }

    // MARK: - Outcome

    private var outcome: CompletionOutcome {
        CompletionOutcome(
            kind: .success,
            systemImage: viewModel.reachedTarget ? "star.fill" : "flag.fill",
            title: "Game Over",
            accessibilityLabel: Text("Game Over. Score: \(viewModel.score)")
        )
    }

    // MARK: - CTA (Close only — OQ-004-3)

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

    private var elapsedLabel: String {
        let secs = viewModel.elapsedSeconds
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }
}
