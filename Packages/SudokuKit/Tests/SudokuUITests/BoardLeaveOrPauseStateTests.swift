// BoardLeaveOrPauseStateTests — pins #849's per-app wiring of the shared
// `BoardLeaveOrPauseState` mapping (GameShellUI).
//
// CR round 2, Finding 1: Sudoku's clock is NOT idle-gated like MS's —
// `GameSession.start()` runs during `BoardLoaderView`, before this view ever
// mounts, so `status` is always `.playing` (or later) and the clock is
// already running by the time a player can see the toolbar. The Ready
// window is real but narrow: only while BOTH `elapsedSeconds == 0` (no
// wall-clock time has ticked past yet) AND `!canUndo` (no digit
// placed/erased) is pausing genuinely meaningless. `BoardModalOverlayActiveTests`
// covers the sibling `isModalOverlayActive` predicate; this suite covers the
// toggle's own state selection (`BoardView.leaveOrPauseState`).

import Testing
@testable import SudokuUI
import GameShellUI
import Persistence
import PersistenceTesting
import SudokuEngine
import SudokuGameState
import SudokuKitTesting
import SudokuPersistence

@Suite("BoardView.leaveOrPauseState (#849)")
@MainActor
struct BoardLeaveOrPauseStateTests {

    private static let clues =
        ".34678912" +
        "672195348" +
        "198342567" +
        "859761423" +
        "426853791" +
        "713924856" +
        "961537284" +
        "287419635" +
        "345286179"

    private static let identity = PuzzleIdentity(
        puzzleId: "practice-easy-leaveOrPause-849",
        kind: .practice,
        difficulty: .easy
    )

    private static func board(
        status: GameSessionStatus,
        elapsedSeconds: Int,
        canUndo: Bool
    ) throws -> BoardView {
        let puzzleBoard = try Board(clues: Self.clues)
        let viewModel = GameViewModel(
            identity: Self.identity,
            board: puzzleBoard,
            status: status,
            elapsedSeconds: elapsedSeconds,
            mistakeCount: 0,
            canUndo: canUndo
        )
        return BoardView(viewModel: viewModel, path: nil)
    }

    @Test("playing, zero elapsed, no move made yet resolves to leaveReady")
    func freshPlayingResolvesToLeaveReady() throws {
        let boardView = try Self.board(status: .playing, elapsedSeconds: 0, canUndo: false)
        #expect(boardView.leaveOrPauseState == .leaveReady)
    }

    @Test("playing, zero elapsed, after a move resolves to pause")
    func freshPlayingWithMoveResolvesToPause() throws {
        let boardView = try Self.board(status: .playing, elapsedSeconds: 0, canUndo: true)
        #expect(boardView.leaveOrPauseState == .pause)
    }

    // Finding 1's exact motivating scenario: a player who has only toggled
    // pencil notes (never touches `undoStack` — see `GameSession.toggleNote`,
    // which does not call `undoStack.push`, unlike `placeDigit`/`clearDigit`)
    // while the wall clock keeps running. `canUndo` stays false, but the
    // clock is no longer at zero — Pause must be offered, not Leave.
    @Test("playing, elapsed > 0, pencil-only (canUndo false) resolves to pause")
    func runningClockPencilOnlyResolvesToPause() throws {
        let boardView = try Self.board(status: .playing, elapsedSeconds: 1, canUndo: false)
        #expect(boardView.leaveOrPauseState == .pause)
    }

    @Test("playing, elapsed > 0, after a move resolves to pause")
    func runningClockWithMoveResolvesToPause() throws {
        let boardView = try Self.board(status: .playing, elapsedSeconds: 10, canUndo: true)
        #expect(boardView.leaveOrPauseState == .pause)
    }

    @Test("paused resolves to resume regardless of elapsed/canUndo")
    func pausedResolvesToResume() throws {
        #expect(try Self.board(status: .paused, elapsedSeconds: 10, canUndo: true).leaveOrPauseState == .resume)
        #expect(try Self.board(status: .paused, elapsedSeconds: 0, canUndo: false).leaveOrPauseState == .resume)
    }

    // MARK: - Empirical proof the Ready window is reachable (Finding 1)
    //
    // Exercises the LIVE `GameSession` + `GameViewModel` path (not the
    // snapshot-init seam above) the way `BoardLoaderView` actually does:
    // `startOrResume()` calls `session.start()`, which sets `runningSince =
    // clock.now` — `GameSessionElapsedTests.startAtZero` (SudokuCoreKit)
    // already pins that `elapsedSeconds == 0` at that exact instant. This
    // test closes the loop up through `GameViewModel` to `BoardView`: a
    // freshly-opened board — no digit placed, no wall-clock time ticked yet
    // — resolves to `.leaveReady`, exactly the window the fix above targets.
    @Test("live startOrResume() lands in the reachable Ready window")
    func liveStartOrResumeReachesLeaveReady() async throws {
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

        await viewModel.startOrResume()

        #expect(viewModel.status == .playing)
        #expect(viewModel.elapsedSeconds == 0)
        #expect(viewModel.canUndo == false)
        let boardView = BoardView(viewModel: viewModel, path: nil)
        #expect(boardView.leaveOrPauseState == .leaveReady)
    }

    // MARK: - Finding 2: resumed mid-game boards must not flash the wrong label
    //
    // `BoardLoaderView.mountLoaded` renders `BoardView` (via `state =
    // .loaded(viewModel)`) BEFORE `startOrResume()`'s resync lands. Without
    // `initialCanUndo` threaded at construction, a resumed board with real
    // undo history would default to `canUndo == false` for that frame and
    // could momentarily resolve to `.leaveReady` instead of `.pause`. This
    // pins the fix: constructing with `initialCanUndo: true` (mirroring
    // `BoardLoaderView` passing `!snapshot.undoMoves.isEmpty`) resolves
    // correctly with no live session interaction at all.
    @Test("resumed mid-game construction with initialCanUndo has no transient leaveReady")
    func resumedConstructionWithInitialCanUndoResolvesToPause() throws {
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        let session = GameSession(puzzle: puzzle)
        let viewModel = GameViewModel(
            identity: Self.identity,
            session: session,
            initialBoard: puzzle.clues,
            initialStatus: .playing,
            initialElapsedSeconds: 0,
            initialCanUndo: true,
            persistence: FakePersistence(),
            saveDebounceNanos: 0
        )
        let boardView = BoardView(viewModel: viewModel, path: nil)
        #expect(boardView.leaveOrPauseState == .pause)
    }
}
