// BoardCompletionOverlayTests — verifies that BoardView presents a
// CompletionViewModel overlay when the game reaches .completed in the
// modal (path == nil) context where path-push is a no-op.
//
// Root cause of #610: pushCompletionIfNeeded() silently no-ops when
// path == nil (modal fullScreenCover). Fix: mirror MS's in-board
// overlay pattern, gated by `shouldPresentCompletionOverlay`.
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

    // FALSE: NavigationStack context (path != nil) + completed.
    // This locks the macOS double-present regression: when a board is
    // presented inline with a non-nil path, only pushCompletionIfNeeded()
    // should fire — NOT the overlay.
    @Test("shouldPresentCompletionOverlay: false when completed + path!=nil (macOS regression lock)")
    func overlayPredicateFalseWhenPathNonNil() throws {
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
        #expect(!boardView.shouldPresentCompletionOverlay,
                "overlay predicate must be false when path!=nil — macOS uses push, not overlay")
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
