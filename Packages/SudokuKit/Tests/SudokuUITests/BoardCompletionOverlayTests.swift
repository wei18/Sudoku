// BoardCompletionOverlayTests — verifies that BoardView presents a
// CompletionViewModel overlay when the game reaches .completed, on every
// presentation context (path == nil modal AND path != nil push).
//
// Root cause of #610: pushCompletionIfNeeded() silently no-ops when
// path == nil (modal fullScreenCover). Fix: mirror MS's in-board
// overlay pattern, gated by `shouldPresentCompletionOverlay`.
//
// #667 (SDD-003 2B): the macOS push branch (path != nil) that used to push a
// SEPARATE `.completion` route is gone — its Close only popped that one
// route, stranding the player on the solved board underneath (audit P1).
// `shouldPresentCompletionOverlay` no longer gates on `path`, so the overlay
// is the one completion presentation on both platforms.
//
// Tests in this file use the snapshot-init seam (GameViewModel(identity:board:...))
// so they run without a live GameSession actor.

import Testing
@testable import SudokuUI
import SwiftUI
import GameCenterTesting
import SudokuEngine
import SudokuGameState
import SudokuPersistence

@Suite("BoardView completion overlay (#610)")
@MainActor
struct BoardCompletionOverlayTests {

    // Full 81-cell solution — no empty cells.
    private static let solvedClues =
        "534678912" +
        "672195348" +
        "198342567" +
        "859761423" +
        "426853791" +
        "713924856" +
        "961537284" +
        "287419635" +
        "345286179"

    private static let dailyIdentity = PuzzleIdentity(
        puzzleId: "2026-06-24-easy",
        kind: .daily,
        difficulty: .easy
    )

    private static let practiceIdentity = PuzzleIdentity(
        puzzleId: "practice-easy-abc123",
        kind: .practice,
        difficulty: .easy
    )

    // MARK: - shouldPresentCompletionOverlay predicate

    // TRUE: modal context (path == nil) + completed status.
    @Test("shouldPresentCompletionOverlay: true when completed + path==nil")
    func overlayPredicateTrueForModalCompleted() throws {
        let board = try Board(clues: Self.solvedClues)
        let viewModel = GameViewModel(
            identity: Self.dailyIdentity,
            board: board,
            status: .completed,
            elapsedSeconds: 123,
            mistakeCount: 0
        )
        let boardView = BoardView(viewModel: viewModel, path: nil)
        #expect(boardView.shouldPresentCompletionOverlay,
                "overlay predicate must be true when path==nil and status==.completed")
    }

    // FALSE: still playing — overlay must not appear mid-game.
    @Test("shouldPresentCompletionOverlay: false when playing + path==nil")
    func overlayPredicateFalseWhilePlaying() throws {
        let clues =
            ".34678912" +
            "672195348" +
            "198342567" +
            "859761423" +
            "426853791" +
            "713924856" +
            "961537284" +
            "287419635" +
            "345286179"
        let board = try Board(clues: clues)
        let viewModel = GameViewModel(
            identity: Self.dailyIdentity,
            board: board,
            status: .playing,
            elapsedSeconds: 50,
            mistakeCount: 0
        )
        let boardView = BoardView(viewModel: viewModel, path: nil)
        #expect(!boardView.shouldPresentCompletionOverlay,
                "overlay predicate must be false while status==.playing")
    }

    // TRUE: NavigationStack context (path != nil) + completed.
    // #667 (SDD-003 2B): locks the fix for the macOS strand-on-solved-board
    // bug (audit P1) — the overlay must fire regardless of push vs modal
    // context; only Close's exit route (`exitToHub`) differs by context.
    @Test("shouldPresentCompletionOverlay: true when completed + path!=nil (macOS uses the overlay too)")
    func overlayPredicateTrueWhenPathNonNil() throws {
        let board = try Board(clues: Self.solvedClues)
        let viewModel = GameViewModel(
            identity: Self.dailyIdentity,
            board: board,
            status: .completed,
            elapsedSeconds: 90,
            mistakeCount: 0
        )
        var routes: [AppRoute] = []
        let path = Binding(get: { routes }, set: { routes = $0 })
        let boardView = BoardView(viewModel: viewModel, path: path)
        #expect(boardView.shouldPresentCompletionOverlay,
                "overlay predicate must be true when path!=nil — macOS now uses the overlay, not a push")
    }

    // MARK: - exitToHub (#667 audit P1: "Close always exits to hub")

    // Push context (path != nil): the board is the top stack entry (no more
    // separately-pushed `.completion` route), so Close must pop exactly that
    // one entry, landing on whatever hub pushed the board.
    @Test("exitToHub: push context pops the board's own stack entry, landing on the hub")
    func exitToHubPopsBoardEntryInPushContext() throws {
        let board = try Board(clues: Self.solvedClues)
        let viewModel = GameViewModel(
            identity: Self.dailyIdentity,
            board: board,
            status: .completed,
            elapsedSeconds: 42,
            mistakeCount: 0
        )
        var routes: [AppRoute] = [.daily, .board(puzzleId: Self.dailyIdentity.puzzleId)]
        let path = Binding(get: { routes }, set: { routes = $0 })
        let boardView = BoardView(viewModel: viewModel, path: path)

        boardView.exitToHub(dismiss: EnvironmentValues().dismiss)

        #expect(routes == [.daily],
                "Close must pop only the board's own entry — never strand the player on the solved board")
    }

    // Defensive: an already-empty path (shouldn't happen in production, the
    // board itself is always a pushed entry) must not crash on removeLast().
    @Test("exitToHub: push context no-ops when path is already empty")
    func exitToHubNoOpsWhenPathEmpty() throws {
        let board = try Board(clues: Self.solvedClues)
        let viewModel = GameViewModel(
            identity: Self.dailyIdentity,
            board: board,
            status: .completed,
            elapsedSeconds: 42,
            mistakeCount: 0
        )
        var routes: [AppRoute] = []
        let path = Binding(get: { routes }, set: { routes = $0 })
        let boardView = BoardView(viewModel: viewModel, path: path)

        boardView.exitToHub(dismiss: EnvironmentValues().dismiss)

        #expect(routes.isEmpty)
    }

    // MARK: - makeCompletionViewModel content checks

    // Daily puzzle → leaderboardId is non-nil.
    @Test("makeCompletionViewModel: carries correct puzzleId for daily")
    func completionVMCarriesCorrectPuzzleId() throws {
        let board = try Board(clues: Self.solvedClues)
        let viewModel = GameViewModel(
            identity: Self.dailyIdentity,
            board: board,
            status: .completed,
            elapsedSeconds: 120,
            mistakeCount: 2
        )
        let boardView = BoardView(viewModel: viewModel, gameCenter: FakeGameCenterClient(), path: nil)
        let cvm = boardView.makeCompletionViewModel()
        #expect(cvm.puzzleId == Self.dailyIdentity.puzzleId,
                "CompletionViewModel.puzzleId must match the board identity")
        #expect(cvm.leaderboardId != nil,
                "Daily solve must carry a non-nil leaderboardId for GC submission")
    }

    // Practice puzzle → leaderboardId must be nil (no GC leaderboard for practice).
    @Test("makeCompletionViewModel: nil leaderboardId for practice puzzle")
    func completionVMNilLeaderboardForPractice() throws {
        let board = try Board(clues: Self.solvedClues)
        let viewModel = GameViewModel(
            identity: Self.practiceIdentity,
            board: board,
            status: .completed,
            elapsedSeconds: 80,
            mistakeCount: 0
        )
        let boardView = BoardView(viewModel: viewModel, path: nil)
        let cvm = boardView.makeCompletionViewModel()
        #expect(cvm.leaderboardId == nil,
                "Practice solve must have nil leaderboardId — no GC leaderboard")
    }
}
