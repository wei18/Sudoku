// MinesweeperShowcaseSessionTests — verifies the DEBUG showcase-board
// builder produces a deterministic, marketing-ready mid-game board (#1054).
//
// Assertions:
//   1. Exactly 3 flagged cells, all real mines (never a false flag).
//   2. Every flag has a FORCING WITNESS — CR round 2 (PM ruling, strengthens
//      round 1's adjacency-only check): a revealed neighbor cell whose
//      displayed number equals its own count of non-revealed neighbors,
//      which pins every one of those non-revealed neighbors (the flag
//      included) as a certain mine by the basic single-constraint count
//      rule. Computed fresh from the built board for each flag — no
//      hard-coded coordinates — so a future seed/algorithm change that
//      breaks the property fails this test instead of silently shipping a
//      guessed flag.
//   3. At least one revealed cell (the board looks "played", not fresh).
//   4. Status is `.playing` (board fully visible, no pause overlay).
//   5. The snapshot is deterministic across every access.
//   6. CR round 1 (blocker): a seeded `MinesweeperGameViewModel`'s `reveal` /
//      `toggleFlag` must be no-ops — proving `isSeeded` actually gates every
//      mutator, not just `refresh()`.
//
// Tests run in DEBUG only (the builder is not compiled in Release).

#if DEBUG

import Testing
@testable import MinesweeperUI
import MinesweeperEngine
import MinesweeperGameState

@Suite("MinesweeperShowcaseSession")
struct MinesweeperShowcaseSessionTests {

    @Test("snapshot flags exactly 3 real mines")
    func showcaseSnapshotFlagsThreeRealMines() {
        let snapshot = MinesweeperShowcaseSession.snapshot
        let flaggedIndices = snapshot.cells.indices.filter { snapshot.cells[$0].state == .flagged }
        #expect(flaggedIndices.count == 3, "expected 3 flagged cells, got \(flaggedIndices.count)")
        for index in flaggedIndices {
            #expect(snapshot.cells[index].isMine, "flagged cell at \(index) must be a real mine")
        }
    }

    @Test("every flag has a forcing witness (basic single-constraint count rule)")
    func showcaseSnapshotFlagsAreForcedNotGuesses() {
        let snapshot = MinesweeperShowcaseSession.snapshot
        // Reconstruct an engine from the snapshot's own cells (mines already
        // placed) so the witness is computed against the EXACT built board,
        // not re-derived from a fresh reveal — this is what the production
        // builder itself checked before flagging.
        let engine = MinesweeperEngine(
            difficulty: snapshot.difficulty,
            seed: snapshot.seed,
            cells: snapshot.cells,
            minesPlaced: true,
            isLost: false
        )
        let columns = snapshot.columns
        let flaggedIndices = snapshot.cells.indices.filter { snapshot.cells[$0].state == .flagged }
        for index in flaggedIndices {
            let row = index / columns
            let col = index % columns
            guard let witnessIndex = MinesweeperShowcaseSession.forcingWitness(atIndex: index, engine: engine) else {
                Issue.record("flag at (\(row),\(col)) has NO forcing witness — it is a guess, not a deduction")
                continue
            }
            let witnessRow = witnessIndex / columns
            let witnessCol = witnessIndex % columns
            let witnessCount = engine.cells[witnessIndex].neighborMineCount
            #expect(
                engine.cells[witnessIndex].state == .revealed,
                "witness (\(witnessRow),\(witnessCol)) for flag at (\(row),\(col)) must be revealed"
            )
            print("flag (\(row),\(col)) witness=(\(witnessRow),\(witnessCol)) count=\(witnessCount)")
        }
    }

    @Test("snapshot has at least one revealed cell")
    func showcaseSnapshotHasRevealedCells() {
        let snapshot = MinesweeperShowcaseSession.snapshot
        let revealedCount = snapshot.cells.filter { $0.state == .revealed }.count
        #expect(revealedCount > 0, "expected at least one revealed cell, got 0")
    }

    @Test("snapshot status is .playing")
    func showcaseSnapshotIsPlaying() {
        #expect(MinesweeperShowcaseSession.snapshot.status == .playing)
    }

    @Test("snapshot is deterministic across every access")
    func showcaseSnapshotIsDeterministic() {
        let first = MinesweeperShowcaseSession.snapshot
        let second = MinesweeperShowcaseSession.snapshot
        #expect(first == second, "showcase snapshot must be bit-identical across accesses")
    }

    @MainActor
    @Test("a seeded VM's reveal(row:col:) is a no-op")
    func seededViewModelRevealIsNoOp() async {
        let viewModel = MinesweeperGameViewModel(seeded: MinesweeperShowcaseSession.snapshot)
        let before = viewModel.snapshot
        // Target a cell that is NOT already revealed/flagged, so a real
        // mutation (were the guard missing) would visibly change the board.
        let columns = before.columns
        guard let targetIndex = before.cells.indices.first(where: { before.cells[$0].state == .hidden }) else {
            Issue.record("fixture has no hidden cell to target")
            return
        }
        await viewModel.reveal(row: targetIndex / columns, col: targetIndex % columns)
        #expect(viewModel.snapshot == before, "seeded VM's reveal(row:col:) must leave the board bit-identical")
    }

    @MainActor
    @Test("a seeded VM's toggleFlag(row:col:) is a no-op")
    func seededViewModelToggleFlagIsNoOp() async {
        let viewModel = MinesweeperGameViewModel(seeded: MinesweeperShowcaseSession.snapshot)
        let before = viewModel.snapshot
        let columns = before.columns
        guard let targetIndex = before.cells.indices.first(where: { before.cells[$0].state == .hidden }) else {
            Issue.record("fixture has no hidden cell to target")
            return
        }
        await viewModel.toggleFlag(row: targetIndex / columns, col: targetIndex % columns)
        #expect(viewModel.snapshot == before, "seeded VM's toggleFlag(row:col:) must leave the board bit-identical")
    }
}

#endif
