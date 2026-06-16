// MinesweeperNearWinSessionTests — verifies that the DEBUG near-win session
// builder produces a board that is exactly one reveal from winning.
//
// Covers #510 uitest hook. Assertions:
//   1. Exactly one non-mine cell is hidden (the one safe cell remaining).
//   2. The last hidden safe cell is at (lastSafeRow, lastSafeCol).
//   3. The session is in `.paused` state (needs one resume tap before winning).
//   4. The result is deterministic across calls.
//
// Tests run in DEBUG only (the builder is not compiled in Release).

#if DEBUG

import Testing
@testable import MinesweeperUI
import MinesweeperEngine
import MinesweeperGameState

@Suite("MinesweeperNearWinSession")
@MainActor
struct MinesweeperNearWinSessionTests {

    @Test("build() produces a session with exactly one hidden safe cell")
    func nearWinSessionHasOneHiddenSafeCell() async {
        let nearWin = await MinesweeperNearWinSession.build()
        let snapshot = await nearWin.viewModel.session.snapshot()

        let hiddenSafeCount = snapshot.cells.filter { !$0.isMine && $0.state == .hidden }.count
        #expect(hiddenSafeCount == 1, "near-win session must have 1 hidden safe cell, got \(hiddenSafeCount)")
    }

    @Test("build() lastSafeRow/lastSafeCol points to the one hidden safe cell")
    func nearWinLastSafeCellCoordinatesAreCorrect() async {
        let nearWin = await MinesweeperNearWinSession.build()
        let snapshot = await nearWin.viewModel.session.snapshot()

        let difficulty = snapshot.difficulty
        let row = nearWin.lastSafeRow
        let col = nearWin.lastSafeCol
        let idx = row * difficulty.columns + col
        let cell = snapshot.cells[idx]

        #expect(!cell.isMine, "lastSafe cell at (\(row),\(col)) must not be a mine")
        #expect(cell.state == .hidden, "lastSafe cell must be hidden, got \(cell.state)")
    }

    @Test("build() session is .paused (needs one resume tap before winning)")
    func nearWinSessionIsPaused() async {
        let nearWin = await MinesweeperNearWinSession.build()
        let status = await nearWin.viewModel.session.status
        #expect(status == .paused, "near-win session must start .paused, got \(status)")
    }

    @Test("build() produces deterministic result (same coordinates on every call)")
    func nearWinSessionIsDeterministic() async {
        let first = await MinesweeperNearWinSession.build()
        let second = await MinesweeperNearWinSession.build()

        let firstRow = first.lastSafeRow
        let secondRow = second.lastSafeRow
        #expect(firstRow == secondRow, "lastSafeRow must be deterministic: \(firstRow) ≠ \(secondRow)")

        let firstCol = first.lastSafeCol
        let secondCol = second.lastSafeCol
        #expect(firstCol == secondCol, "lastSafeCol must be deterministic: \(firstCol) ≠ \(secondCol)")
    }
}

#endif
