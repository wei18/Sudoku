import SwiftUI
import Testing
@testable import GameShellUI

// MARK: - CompletionScreen (issue #418 / #698)
//
// The shared game-over / completion body, extracted from SudokuUI.CompletionView
// + MinesweeperUI.MinesweeperCompletionView. These tests pin one contract:
//   genericity / GameCenter-decoupling — it instantiates with plain outcome
//   values and injected closures, with no GameCenterClient / GameKit /
//   monetization types, so it can be mounted by either game (compile-only
//   sentinel, mirrors the sibling Settings sentinels). If a future change
//   re-couples the body to GameCenterClient, this target stops compiling.
//
// #698: the leaderboard-zone 5-state fetch/present machine (the leaderboard-
// state enum, the leaderboard-row value type, and the `onSignIn`/
// `onRetryLeaderboard`/`loadedAccessory` params) was deleted — both apps
// hardcoded `state: .hidden` since v2.6 and it never rendered. The body is now
// hero + actions + footer only, so these tests just cover both outcome kinds +
// minimal construction.
//
// Pixel-level verification of the shared body lives in the two apps' existing
// snapshot suites (SudokuUITests.CompletionViewTests +
// MinesweeperUITests.MinesweeperCompletionSnapshotTests), which render every
// outcome through the real wrappers; keeping those baselines byte-identical is
// the regression guard for this refactor.

@Suite("GameShellUI — CompletionScreen")
@MainActor
struct CompletionScreenTests {

    private static let successOutcome = CompletionOutcome(
        kind: .success,
        systemImage: "checkmark.circle.fill",
        title: "Solved!",
        accessibilityLabel: Text("Solved in 4:11")
    )

    private static let failureOutcome = CompletionOutcome(
        kind: .failure,
        systemImage: "burst.fill",
        title: "Boom",
        accessibilityLabel: Text("Boom. Lasted 1:05")
    )

    private func screen(outcome: CompletionOutcome) -> CompletionScreen {
        CompletionScreen(
            outcome: outcome,
            elapsedLabel: "4:11",
            actions: { Color.clear.frame(height: 1) }
        )
    }

    // MARK: - Both outcome kinds

    @Test func successOutcomeRenders() { _ = screen(outcome: Self.successOutcome) }

    @Test func failureOutcomeRenders() { _ = screen(outcome: Self.failureOutcome) }

    // MARK: - Minimal construction (defaults: no actions, no footer)

    @Test func minimalConstruction() {
        _ = CompletionScreen(outcome: Self.successOutcome, elapsedLabel: "4:11")
    }
}
