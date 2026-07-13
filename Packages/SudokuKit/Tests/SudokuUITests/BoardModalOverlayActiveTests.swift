// BoardModalOverlayActiveTests — #763: pins `BoardView.isModalOverlayActive`,
// the predicate that feeds the `BoardModalOverlayActivePreferenceKey`
// published right after `BoardView`'s Pause/Completion `.overlay { … }`. The
// macOS split-view shell (`RootShellView`) masks + disables the sidebar while
// this is true, so the predicate MUST exactly track the overlay's own
// visibility condition (`completionViewModel != nil || viewModel.isPaused`).
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

@Suite("BoardView.isModalOverlayActive (#763)")
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
        #expect(boardView.isModalOverlayActive,
                "isModalOverlayActive must be true while viewModel.isPaused, mirroring the .overlay condition")
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
        #expect(!boardView.isModalOverlayActive,
                "isModalOverlayActive must be false while playing and no completionViewModel is mounted")
    }
}
