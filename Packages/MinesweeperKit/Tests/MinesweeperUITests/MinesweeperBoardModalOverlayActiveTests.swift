// MinesweeperBoardModalOverlayActiveTests — #763 / #1020: pins
// `MinesweeperBoardView.modalOverlayPresentation`, the single key handed to
// `.boardModalOverlay(presentation:content:)`. That one value drives BOTH the
// in-place overlay and the hoisted copy `RootShellView` renders outside its
// `TabView` on macOS, so the branch order here MUST mirror the overlay
// content's: completion (terminal + completionViewModel mounted) wins, then
// pause, then the idle-leave confirmation, else `nil`.
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

@Suite("MinesweeperBoardView.modalOverlayPresentation (#763)")
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
        #expect(boardView.modalOverlayPresentation == .pause,
                "presentation must be .pause while viewModel.isPaused, mirroring the overlay branch")
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
        #expect(boardView.modalOverlayPresentation == .completion,
                "presentation must be .completion when terminal + completionViewModel is mounted")
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
        #expect(boardView.modalOverlayPresentation == nil,
                "modalOverlayPresentation must be nil while playing with no pause/completion/idle-leave state")
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
        #expect(boardView.modalOverlayPresentation == nil,
                "modalOverlayPresentation must stay nil until completionViewModel is actually seeded")
    }
}
