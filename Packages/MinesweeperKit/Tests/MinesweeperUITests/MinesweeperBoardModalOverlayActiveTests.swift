// MinesweeperBoardModalOverlayActiveTests — #763: pins
// `MinesweeperBoardView.isModalOverlayActive`, the predicate that feeds the
// `BoardModalOverlayActivePreferenceKey` published right after
// `MinesweeperBoardView`'s Pause/Completion `.overlay { … }`. The macOS
// split-view shell (`RootShellView`) masks + disables the sidebar while this
// is true, so the predicate MUST exactly track the overlay's own visibility
// condition: `(viewModel.isTerminal && completionViewModel != nil) ||
// viewModel.isPaused || showIdleLeaveOverlay`.
//
// Unlike Sudoku's `BoardView`, the `completionViewModelForSnapshot` init seam
// (#388/#315) lets tests pre-seed `completionViewModel` directly, so the
// terminal+completion branch is directly constructible here (no need to
// document it as a manual-only check). `showIdleLeaveOverlay` stays a private
// `@State` with no init seam — its branch is left to the existing #681
// coverage + manual verification (idle-board Leave affordance), matching the
// `isPaused` / `isTerminal` branches' precedent of testing via constructible
// VM state only.

import Testing
@testable import MinesweeperUI
import MinesweeperEngine
import MinesweeperGameState

@Suite("MinesweeperBoardView.isModalOverlayActive (#763)")
@MainActor
struct MinesweeperBoardModalOverlayActiveTests {

    private static let cols = Difficulty.beginner.columns
    private static let rows = Difficulty.beginner.rows

    private static func cells() -> [Cell] {
        Array(repeating: Cell(state: .hidden), count: rows * cols)
    }

    @Test("true when the session is paused")
    func trueWhenPaused() {
        let snapshot = MinesweeperSessionSnapshot(
            difficulty: .beginner,
            cells: Self.cells(),
            status: .paused,
            elapsedSeconds: 5,
            mineCount: Difficulty.beginner.mineCount,
            flagCount: 0
        )
        let boardView = MinesweeperBoardView(
            viewModel: MinesweeperGameViewModel(seeded: snapshot),
            suppressTickerForSnapshot: true,
            tapModeDefaults: BoardTestDefaults.store
        )
        #expect(boardView.isModalOverlayActive,
                "isModalOverlayActive must be true while viewModel.isPaused, mirroring the .overlay condition")
    }

    @Test("true when terminal with a mounted completionViewModel")
    func trueWhenTerminalWithCompletion() {
        let snapshot = MinesweeperSessionSnapshot(
            difficulty: .beginner,
            cells: Self.cells(),
            status: .lost,
            elapsedSeconds: 5,
            mineCount: Difficulty.beginner.mineCount,
            flagCount: 0
        )
        let completionVM = MinesweeperCompletionViewModel(
            didWin: false,
            elapsedSeconds: 5,
            leaderboardId: MinesweeperLeaderboardID.easyDaily
        )
        let boardView = MinesweeperBoardView(
            viewModel: MinesweeperGameViewModel(seeded: snapshot),
            suppressTickerForSnapshot: true,
            completionViewModelForSnapshot: completionVM,
            tapModeDefaults: BoardTestDefaults.store
        )
        #expect(boardView.isModalOverlayActive,
                "isModalOverlayActive must be true when terminal + completionViewModel is mounted")
    }

    @Test("false while actively playing with no overlay state")
    func falseWhilePlaying() {
        let snapshot = MinesweeperSessionSnapshot(
            difficulty: .beginner,
            cells: Self.cells(),
            status: .playing,
            elapsedSeconds: 5,
            mineCount: Difficulty.beginner.mineCount,
            flagCount: 0
        )
        let boardView = MinesweeperBoardView(
            viewModel: MinesweeperGameViewModel(seeded: snapshot),
            suppressTickerForSnapshot: true,
            tapModeDefaults: BoardTestDefaults.store
        )
        #expect(!boardView.isModalOverlayActive,
                "isModalOverlayActive must be false while playing with no pause/completion/idle-leave state")
    }

    @Test("false when terminal but no completionViewModel is mounted yet")
    func falseWhenTerminalWithoutCompletion() {
        let snapshot = MinesweeperSessionSnapshot(
            difficulty: .beginner,
            cells: Self.cells(),
            status: .won,
            elapsedSeconds: 5,
            mineCount: Difficulty.beginner.mineCount,
            flagCount: 0
        )
        let boardView = MinesweeperBoardView(
            viewModel: MinesweeperGameViewModel(seeded: snapshot),
            suppressTickerForSnapshot: true,
            tapModeDefaults: BoardTestDefaults.store
        )
        #expect(!boardView.isModalOverlayActive,
                "isModalOverlayActive must stay false until completionViewModel is actually seeded")
    }
}
