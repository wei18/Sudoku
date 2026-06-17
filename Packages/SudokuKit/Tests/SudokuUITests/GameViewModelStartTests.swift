// GameViewModelStartTests — regression net for issue #227.
//
// The pre-fix code had `BoardLoaderView` constructing a `GameSession` and
// leaving it in `.idle`. Every digit-pad tap then failed the `.playing`
// gate inside `GameSession` and was silently absorbed by `runSession`, so
// the user saw a dead board + a frozen 0:00 timer.
//
// The snapshot tests in `BoardViewTests` use the snapshot init seam with
// `status: .playing` and thus could not catch this — they bypass the actor
// entirely. The tests below exercise the LIVE init path that real users hit:
// real `GameSession`, real `Persistence` (fake), assert mutations only land
// after `startOrResume()`.

import Foundation
import SudokuGameState
import Persistence
import PersistenceTesting
import SudokuPersistence
import SudokuEngine
import SudokuKitTesting
import Telemetry
import Testing
@testable import SudokuUI

@MainActor
@Suite("GameViewModel — startOrResume() unblocks mutations (issue #227)")
struct GameViewModelStartTests {

    private static let identity = PuzzleIdentity.practice(salt: 227, difficulty: .easy)

    private func makeLiveViewModel() throws -> (GameViewModel, GameSession) {
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        let session = GameSession(puzzle: puzzle)
        let viewModel = GameViewModel(
            identity: Self.identity,
            session: session,
            initialBoard: puzzle.clues,
            initialStatus: .idle,
            persistence: FakePersistence(),
            saveDebounceNanos: 0
        )
        return (viewModel, session)
    }

    @Test func startOrResume_advancesIdleToPlaying() async throws {
        let (viewModel, session) = try makeLiveViewModel()
        #expect(viewModel.status == .idle)

        await viewModel.startOrResume()

        #expect(viewModel.status == .playing)
        let sessionStatus = await session.status
        #expect(sessionStatus == .playing)
    }

    @Test func placeDigit_landsAfterStartOrResume() async throws {
        // latinSquarePuzzle() defaults to a single empty cell at (0,0);
        // solution digit there is 1. Select that cell and place 1 — only
        // possible if startOrResume has advanced the actor out of `.idle`,
        // which was the regression (#227).
        let (viewModel, _) = try makeLiveViewModel()
        viewModel.selection = GridCoordinate(row: 0, column: 0)

        await viewModel.startOrResume()
        await viewModel.placeDigit(1)

        #expect(viewModel.board.digit(atRow: 0, column: 0) == 1)
    }

    @Test func startOrResume_isIdempotentWhilePlaying() async throws {
        let (viewModel, _) = try makeLiveViewModel()
        await viewModel.startOrResume()
        #expect(viewModel.status == .playing)

        // Calling again should not blow up or regress state.
        await viewModel.startOrResume()
        #expect(viewModel.status == .playing)
    }

    @Test func startOrResume_resumesFromPaused() async throws {
        let (viewModel, _) = try makeLiveViewModel()
        await viewModel.startOrResume()
        await viewModel.pause()
        #expect(viewModel.status == .paused)

        await viewModel.startOrResume()
        #expect(viewModel.status == .playing)
    }
}
