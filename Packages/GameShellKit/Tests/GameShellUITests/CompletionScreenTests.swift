import SwiftUI
import Testing
@testable import GameShellUI

// MARK: - CompletionScreen (issue #418)
//
// The shared game-over / completion body, extracted from SudokuUI.CompletionView
// + MinesweeperUI.MinesweeperCompletionView. These tests pin two contracts:
//   1. genericity / GameCenter-decoupling — it instantiates with PLAIN
//      `CompletionLeaderboardRow` values and injected closures, with no
//      GameCenterClient / GameKit / monetization types, so it can be mounted by
//      either game (compile-only sentinel, mirrors the sibling Settings
//      sentinels). If a future change re-couples the body to GameCenterClient,
//      this target stops compiling.
//   2. every state both apps need renders — loading / loaded / unauthenticated /
//      noLeaderboard (Sudoku #383, shared with MS) / failed, across both outcome
//      kinds (solve-only success + Minesweeper win/loss).
//
// Pixel-level verification of the shared body lives in the two apps' existing
// snapshot suites (SudokuUITests.CompletionViewTests +
// MinesweeperUITests.MinesweeperCompletionSnapshotTests), which render every
// state through the real wrappers; keeping those baselines byte-identical is the
// regression guard for this refactor.

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

    private static let sampleRows = [
        CompletionLeaderboardRow(rank: 1, displayName: "alice", score: "3:48"),
        CompletionLeaderboardRow(rank: 2, displayName: "bob", score: "3:55"),
        CompletionLeaderboardRow(rank: 3, displayName: "carol", score: "4:02"),
    ]

    private func screen(
        outcome: CompletionOutcome,
        state: CompletionScreenState,
        onSignIn: (() -> Void)? = nil
    ) -> CompletionScreen {
        CompletionScreen(
            outcome: outcome,
            elapsedLabel: "4:11",
            state: state,
            onSignIn: onSignIn,
            onRetryLeaderboard: {},
            loadedAccessory: { Color.clear.frame(height: 1) },
            actions: { Color.clear.frame(height: 1) }
        )
    }

    // MARK: - All states, success outcome (mirrors Sudoku's solve-only set)

    @Test func loading() { _ = screen(outcome: Self.successOutcome, state: .loading) }

    @Test func loaded() {
        _ = screen(outcome: Self.successOutcome, state: .loaded(Self.sampleRows))
    }

    @Test func unauthenticatedWithSignIn() {
        _ = screen(outcome: Self.successOutcome, state: .unauthenticated, onSignIn: {})
    }

    @Test func unauthenticatedNoSignIn() {
        // Minesweeper passes `onSignIn: nil` → copy only, no button.
        _ = screen(outcome: Self.successOutcome, state: .unauthenticated)
    }

    @Test func noLeaderboard() {
        // Sudoku Practice (#383); the shared body gives MS the same state too.
        _ = screen(outcome: Self.successOutcome, state: .noLeaderboard)
    }

    @Test func failed() { _ = screen(outcome: Self.successOutcome, state: .failed) }

    // MARK: - Failure outcome (Minesweeper loss hero)

    @Test func failureOutcomeRenders() {
        _ = screen(outcome: Self.failureOutcome, state: .unauthenticated)
    }

    // MARK: - Minimal construction (defaults: no accessory, no actions, no footer)

    @Test func minimalConstruction() {
        _ = CompletionScreen(
            outcome: Self.successOutcome,
            elapsedLabel: "4:11",
            state: .loading,
            onRetryLeaderboard: {}
        )
    }
}
