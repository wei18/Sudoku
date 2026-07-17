// MinesweeperLeaveOrPauseStateTests — pins #849's per-app wiring of the
// shared `BoardLeaveOrPauseState` mapping (GameShellUI): MS's pre-first-tap
// `.idle` board (mines not yet placed) resolves to `.leaveReady`, exactly
// like it did via the pre-#849 hand-written `showIdleLeaveOverlay` branch.
// `MinesweeperBoardModalOverlayActiveTests` covers the sibling
// `isModalOverlayActive` predicate; this suite covers the toggle's own
// state selection (`MinesweeperBoardView.leaveOrPauseState`).

import Testing
@testable import MinesweeperUI
import GameShellUI
import MinesweeperEngine
import MinesweeperGameState

@Suite("MinesweeperBoardView.leaveOrPauseState (#849)")
@MainActor
struct MinesweeperLeaveOrPauseStateTests {

    private static let cols = Difficulty.beginner.columns
    private static let rows = Difficulty.beginner.rows

    private static func cells() -> [Cell] {
        Array(repeating: Cell(state: .hidden), count: rows * cols)
    }

    private static func board(status: MinesweeperSessionStatus) -> MinesweeperBoardView {
        let snapshot = MinesweeperSessionSnapshot(
            difficulty: .beginner,
            cells: Self.cells(),
            status: status,
            elapsedSeconds: 5,
            mineCount: Difficulty.beginner.mineCount,
            flagCount: 0
        )
        return MinesweeperBoardView(
            viewModel: MinesweeperGameViewModel(seeded: snapshot),
            suppressTickerForSnapshot: true,
            tapModeDefaults: BoardTestDefaults.store
        )
    }

    @Test("idle (pre-first-tap) resolves to leaveReady")
    func idleResolvesToLeaveReady() {
        #expect(Self.board(status: .idle).leaveOrPauseState == .leaveReady)
    }

    @Test("playing resolves to pause")
    func playingResolvesToPause() {
        #expect(Self.board(status: .playing).leaveOrPauseState == .pause)
    }

    @Test("paused resolves to resume")
    func pausedResolvesToResume() {
        #expect(Self.board(status: .paused).leaveOrPauseState == .resume)
    }
}
