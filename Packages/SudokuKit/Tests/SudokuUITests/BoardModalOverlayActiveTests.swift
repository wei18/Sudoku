// BoardModalOverlayActiveTests — #763 / #1020: pins `BoardView.modalOverlayPresentation`,
// the single key handed to `.boardModalOverlay(presentation:content:)`. That
// one value drives BOTH the in-place overlay and the hoisted copy
// `RootShellView` renders outside its `TabView` on macOS, so the branch order
// here MUST mirror the overlay content's: completion (completionViewModel
// mounted) wins, then pause, else `nil`.
//
// The `completionViewModel`-driven half of the predicate is exercised
// structurally by `BoardCompletionOverlayTests.shouldPresentCompletionOverlay`
// (same underlying `.completed` transition that seeds `completionViewModel`
// via `BoardView.body`'s `.onChange`); `completionViewModel` is a private
// `@State` seeded only through that live view lifecycle, so it isn't
// independently constructible here without building new test machinery. The
// `isPaused` half below IS directly constructible via the snapshot-init seam
// and is covered exhaustively.

import Testing
@testable import SudokuUI
import SudokuEngine
import SudokuGameState
import SudokuPersistence

@Suite("BoardView.modalOverlayPresentation (#763)")
@MainActor
struct BoardModalOverlayActiveTests {

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
        puzzleId: "practice-easy-modal-763",
        kind: .practice,
        difficulty: .easy
    )

    @Test("true when the session is paused")
    func trueWhenPaused() throws {
        let board = try Board(clues: Self.clues)
        let viewModel = GameViewModel(
            identity: Self.identity,
            board: board,
            status: .paused,
            elapsedSeconds: 10,
            mistakeCount: 0
        )
        let boardView = BoardView(viewModel: viewModel, path: nil)
        #expect(boardView.modalOverlayPresentation == .pause,
                "presentation must be .pause while viewModel.isPaused, mirroring the overlay branch")
    }

    @Test("false while actively playing")
    func falseWhilePlaying() throws {
        let board = try Board(clues: Self.clues)
        let viewModel = GameViewModel(
            identity: Self.identity,
            board: board,
            status: .playing,
            elapsedSeconds: 10,
            mistakeCount: 0
        )
        let boardView = BoardView(viewModel: viewModel, path: nil)
        #expect(boardView.modalOverlayPresentation == nil,
                "presentation must be nil while playing with no completionViewModel mounted")
    }
}
