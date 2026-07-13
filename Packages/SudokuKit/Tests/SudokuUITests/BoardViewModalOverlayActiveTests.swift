// BoardViewModalOverlayActiveTests — locks `BoardView.isModalOverlayActive`
// (#763): true exactly when the board's own `.overlay` shows the completion
// surface or the pause menu. `NavigationStackHost` (GameShellUI) masks the
// macOS sidebar off this signal — see ModalOverlayPreference.swift — so a
// wrong value here means the sidebar silently stops being masked (or gets
// masked when it shouldn't).
//
// Mirrors BoardCompletionOverlayTests' pattern: exercise the `internal`
// boolean directly via the snapshot-init seam (GameViewModel(identity:board:...))
// rather than standing up a live SwiftUI render tree.

import Testing
@testable import SudokuUI
import SwiftUI
import SudokuEngine
import SudokuGameState
import SudokuPersistence

@Suite("BoardView — isModalOverlayActive (#763)")
@MainActor
struct BoardViewModalOverlayActiveTests {

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

    private static let inProgressClues =
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
        puzzleId: "test-easy",
        kind: .practice,
        difficulty: .easy
    )

    @Test("false while playing, not paused — no overlay, sidebar stays live")
    func falseWhilePlayingUnpaused() throws {
        let board = try Board(clues: Self.inProgressClues)
        let viewModel = GameViewModel(
            identity: Self.identity,
            board: board,
            status: .playing,
            elapsedSeconds: 10,
            mistakeCount: 0
        )
        let boardView = BoardView(viewModel: viewModel, path: nil)
        #expect(!boardView.isModalOverlayActive)
    }

    @Test("true while paused — the pause overlay is up")
    func trueWhilePaused() throws {
        let board = try Board(clues: Self.inProgressClues)
        let viewModel = GameViewModel(
            identity: Self.identity,
            board: board,
            status: .paused,
            elapsedSeconds: 10,
            mistakeCount: 0
        )
        let boardView = BoardView(viewModel: viewModel, path: nil)
        #expect(boardView.isModalOverlayActive)
    }

    @Test("false when completed but the completion overlay's VM hasn't been built yet")
    func falseWhenCompletedWithoutCompletionViewModel() throws {
        let board = try Board(clues: Self.solvedClues)
        let viewModel = GameViewModel(
            identity: Self.identity,
            board: board,
            status: .completed,
            elapsedSeconds: 90,
            mistakeCount: 0
        )
        let boardView = BoardView(viewModel: viewModel, path: nil)
        // Mirrors production: BoardView.body's `.onChange(of: status == .completed)`
        // builds `completionViewModel` — the overlay `if let` (and therefore
        // `isModalOverlayActive`) gates on that VM's presence, not `status`
        // directly. This seam skips that `.onChange`, so the VM is never built.
        #expect(!boardView.isModalOverlayActive,
                "completed status alone (before the VM is built) must not yet report an active overlay")
    }

    @Test("true once the completion overlay's VM is present")
    func trueWhenCompletionViewModelBuilt() throws {
        let board = try Board(clues: Self.solvedClues)
        let viewModel = GameViewModel(
            identity: Self.identity,
            board: board,
            status: .completed,
            elapsedSeconds: 90,
            mistakeCount: 0
        )
        // #763 test seam: installs `completionViewModel` via
        // `State(initialValue:)` at init time — directly assigning `@State`
        // after construction is a documented no-op outside a live render
        // tree (confirmed: `boardView.completionViewModel = x` left
        // `isModalOverlayActive` false in an earlier draft of this test).
        let completionVM = CompletionViewModel(
            puzzleId: Self.identity.puzzleId,
            elapsedSeconds: 90,
            mistakeCount: 0,
            leaderboardId: nil
        )
        let boardView = BoardView(viewModel: viewModel, path: nil, completionViewModelForSnapshot: completionVM)
        #expect(boardView.isModalOverlayActive)
    }

    @Test("true on macOS push context too (path != nil) — mirrors #667's every-platform overlay")
    func trueInPushContextWhenPaused() throws {
        let board = try Board(clues: Self.inProgressClues)
        let viewModel = GameViewModel(
            identity: Self.identity,
            board: board,
            status: .paused,
            elapsedSeconds: 10,
            mistakeCount: 0
        )
        var routes: [AppRoute] = [.daily, .board(puzzleId: Self.identity.puzzleId)]
        let path = Binding(get: { routes }, set: { routes = $0 })
        let boardView = BoardView(viewModel: viewModel, path: path)
        #expect(boardView.isModalOverlayActive,
                "macOS push context (path != nil) must report the same overlay signal as the modal context")
    }
}
