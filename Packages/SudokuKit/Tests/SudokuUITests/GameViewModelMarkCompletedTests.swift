// GameViewModelMarkCompletedTests — regression net for #610 fix *3:
// solving a game must call `persistence.markCompleted(_:)` so the resume
// affordance clears from the hub and Practice/Daily hubs stop offering the
// finished puzzle.
//
// Root cause: `markCompleted` was defined on `PersistenceProtocol` but NEVER
// called in the Sudoku live flow — only test/noop conformers implemented it.
// Fix: detect the `.playing → .completed` edge in `GameViewModel.placeDigit`
// and call `persistence.markCompleted` with a summary derived from the current
// identity.

import Foundation
import SudokuGameState
import Persistence
import PersistenceTesting
import SudokuPersistence
import SudokuEngine
import SudokuKitTesting
import Testing
@testable import SudokuUI

@MainActor
@Suite("GameViewModel — markCompleted on solve (#610)")
struct GameViewModelMarkCompletedTests {

    private static let practiceIdentity = PuzzleIdentity.practice(salt: 42, difficulty: .easy)
    private static let dailyIdentity = PuzzleIdentity(
        puzzleId: "2026-06-24-easy",
        kind: .daily,
        difficulty: .easy
    )

    private func makeViewModel(identity: PuzzleIdentity) -> (GameViewModel, SudokuKitTesting.FakePersistence) {
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        let session = GameSession(puzzle: puzzle)
        let persistence = SudokuKitTesting.FakePersistence()
        let viewModel = GameViewModel(
            identity: identity,
            session: session,
            initialBoard: puzzle.clues,
            initialStatus: .idle,
            persistence: persistence,
            saveDebounceNanos: 0
        )
        return (viewModel, persistence)
    }

    // Completing the puzzle triggers exactly one .markCompleted operation.
    @Test("completing a practice puzzle calls markCompleted once")
    func completingPracticeCallsMarkCompleted() async throws {
        let (viewModel, persistence) = makeViewModel(identity: Self.practiceIdentity)
        viewModel.selection = GridCoordinate(row: 0, column: 0)
        await viewModel.startOrResume()

        // Solve the board (latinSquarePuzzle has one empty cell at (0,0) = digit 1).
        await viewModel.placeDigit(1)

        #expect(viewModel.status == .completed, "game must be completed after placing the final digit")
        let ops = await persistence.operations
        let markCompletedOps = ops.filter {
            if case .markCompleted = $0 { return true }
            return false
        }
        #expect(markCompletedOps.count == 1, "markCompleted must be called exactly once on solve")
    }

    // Completing a daily puzzle also calls markCompleted.
    @Test("completing a daily puzzle calls markCompleted once")
    func completingDailyCallsMarkCompleted() async throws {
        let (viewModel, persistence) = makeViewModel(identity: Self.dailyIdentity)
        viewModel.selection = GridCoordinate(row: 0, column: 0)
        await viewModel.startOrResume()

        await viewModel.placeDigit(1)

        #expect(viewModel.status == .completed)
        let ops = await persistence.operations
        let markCompletedOps = ops.filter {
            if case .markCompleted = $0 { return true }
            return false
        }
        #expect(markCompletedOps.count == 1)
    }

    // Placing a digit that does NOT complete the game must NOT call markCompleted.
    @Test("placing a non-completing digit does not call markCompleted")
    func nonCompletingDigitDoesNotCallMarkCompleted() async throws {
        // Use a practice-hard puzzle with >1 empty cell so placing digit at (0,0)
        // doesn't complete the board. PuzzleFixtures.latinSquarePuzzle() has exactly
        // one empty cell, so to test the non-completion path we set it to a status
        // that's already playing with a non-solved board.
        //
        // Instead: use the snapshot-init seam so we control the board state.
        // A board with status .playing and a given at every cell except (0,0)
        // won't reach .completed from a single place (there are remaining empty cells
        // conceptually — but since latinSquarePuzzle has only ONE empty cell, placing
        // the correct digit WILL solve it). So we place the WRONG digit to trigger
        // the mistake path (still playing after placement).
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        let session = GameSession(puzzle: puzzle)
        let persistence = SudokuKitTesting.FakePersistence()
        let viewModel = GameViewModel(
            identity: Self.practiceIdentity,
            session: session,
            initialBoard: puzzle.clues,
            initialStatus: .idle,
            persistence: persistence,
            saveDebounceNanos: 0
        )
        viewModel.selection = GridCoordinate(row: 0, column: 0)
        await viewModel.startOrResume()

        // Place a wrong digit (2 instead of 1) — should trigger a conflict/mistake
        // rather than completion (latinSquarePuzzle's (0,0) solution is 1).
        await viewModel.placeDigit(2)

        #expect(viewModel.status != .completed, "wrong digit must not complete the game")
        let ops = await persistence.operations
        let markCompletedOps = ops.filter {
            if case .markCompleted = $0 { return true }
            return false
        }
        #expect(markCompletedOps.isEmpty, "markCompleted must NOT be called on a non-completing move")
    }
}
