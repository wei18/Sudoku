// GameViewModelCompletionRouteTests — regression net for the "can't end the
// game" bug: solving the puzzle never surfaced the Completion screen.
//
// Win detection + the `.playing → .completed` transition already worked inside
// `GameSession`, and `resyncFromSession()` already mirrored `status` into the
// VM — but nothing exposed a navigable destination, so the host could never
// push `.completion`. These tests drive a real `GameViewModel` + `GameSession`
// to a solved board and assert the VM publishes `.completion(...)` as
// observable data (the seam the host appends onto its navigation path).

import Foundation
import GameState
import Persistence
import PersistenceTesting
import PuzzleStore
import SudokuEngine
import SudokuKitTesting
import Testing
@testable import SudokuUI

@MainActor
@Suite("GameViewModel — completionRoute surfaces solve → completion")
struct GameViewModelCompletionRouteTests {

    private static let identity = PuzzleIdentity.practice(salt: 999, difficulty: .easy)

    private func makeLiveViewModel() -> GameViewModel {
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        let session = GameSession(puzzle: puzzle)
        return GameViewModel(
            identity: Self.identity,
            session: session,
            initialBoard: puzzle.clues,
            initialStatus: .idle,
            persistence: FakePersistence(),
            saveDebounceNanos: 0
        )
    }

    @Test func completionRoute_isNilWhilePlaying() async {
        let viewModel = makeLiveViewModel()
        await viewModel.startOrResume()

        #expect(viewModel.status == .playing)
        #expect(viewModel.completionRoute == nil)
    }

    @Test func completionRoute_surfacesAfterSolvingBoard() async {
        // latinSquarePuzzle() leaves exactly one empty cell at (0,0); its
        // solution digit is 1. Placing it solves the board → GameSession
        // transitions .playing → .completed and freezes the clock.
        let viewModel = makeLiveViewModel()
        viewModel.selection = GridCoordinate(row: 0, column: 0)

        await viewModel.startOrResume()
        await viewModel.placeDigit(1)

        #expect(viewModel.status == .completed)
        #expect(
            viewModel.completionRoute
                == .completion(
                    puzzleId: Self.identity.puzzleId,
                    elapsedSeconds: viewModel.elapsedSeconds
                )
        )
    }
}
