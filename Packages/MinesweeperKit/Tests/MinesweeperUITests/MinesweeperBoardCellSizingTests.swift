// MinesweeperBoardCellSizingTests — #764: Intermediate/Expert cells were
// pinned to Beginner's 32pt floor on narrow phones, below the 44pt HIG touch
// target. `MinesweeperBoardView.cellSizing(availW:availH:rows:cols:floor:)`
// is the pure three-branch ladder extracted from `boardGrid` so this
// per-difficulty floor behavior can be pinned without hosting a SwiftUI view.
//
// All cases share a single assumed board-area budget (375/402pt offered
// width × 500pt offered height, netting out the #278 2pt inter-cell spacing)
// representative of an iPhone SE-class phone after status bar / mode-toggle
// chrome is subtracted. Widths mirror the two device classes cited in #764
// (375pt = iPhone SE 2nd/3rd gen; 402pt = iPhone 16 Pro Max-class).

import Foundation
import Testing
@testable import MinesweeperUI
import MinesweeperEngine

@Suite("MinesweeperBoardView.cellSizing — per-difficulty floor ladder (#764)")
struct MinesweeperBoardCellSizingTests {

    private static let spacing: CGFloat = 2

    /// Mirrors `boardGrid`'s own `availW`/`availH` derivation: subtract the
    /// inter-cell gaps from the raw offered rect before dividing.
    private func avail(offered: CGFloat, count: Int) -> CGFloat {
        offered - Self.spacing * CGFloat(count - 1)
    }

    // MARK: - Per-difficulty floor mapping

    @Test("Beginner floor stays 32pt")
    func beginnerFloorUnchanged() {
        #expect(MinesweeperBoardView.minCellSide(for: .beginner) == 32)
    }

    @Test("Intermediate floor raised to 44pt (was 32)")
    func intermediateFloorRaised() {
        #expect(MinesweeperBoardView.minCellSide(for: .intermediate) == 44)
    }

    @Test("Expert floor raised to 44pt (was 32)")
    func expertFloorRaised() {
        #expect(MinesweeperBoardView.minCellSide(for: .expert) == 44)
    }

    // MARK: - (a) Beginner 375pt → fitted branch, ~39pt cells, no scroll

    @Test("Beginner at 375pt width fits without scrolling, floor untouched")
    func beginnerAt375FitsNoScroll() {
        let difficulty = Difficulty.beginner
        let sizing = MinesweeperBoardView.cellSizing(
            availW: avail(offered: 375, count: difficulty.columns),
            availH: avail(offered: 500, count: difficulty.rows),
            rows: difficulty.rows,
            cols: difficulty.columns,
            floor: MinesweeperBoardView.minCellSide(for: difficulty)
        )
        #expect(sizing.branch == .fitted)
        #expect(sizing.cellSide == 39)
    }

    // MARK: - (b) Intermediate 375×500 → pinned branch, floor raised 32 → 44

    @Test("Intermediate at 375pt width stays pinned-floor; cellSide rises 32 → 44")
    func intermediateAt375PinnedFloorRaised() {
        let difficulty = Difficulty.intermediate
        let availW = avail(offered: 375, count: difficulty.columns)
        let availH = avail(offered: 500, count: difficulty.rows)

        let before = MinesweeperBoardView.cellSizing(
            availW: availW, availH: availH,
            rows: difficulty.rows, cols: difficulty.columns,
            floor: 32 // pre-#764 shared floor
        )
        let after = MinesweeperBoardView.cellSizing(
            availW: availW, availH: availH,
            rows: difficulty.rows, cols: difficulty.columns,
            floor: MinesweeperBoardView.minCellSide(for: difficulty)
        )

        #expect(before.branch == .pinnedFloorScrollBoth)
        #expect(before.cellSide == 32)
        // Branch shape is unchanged by the raised floor — only cellSide moves.
        #expect(after.branch == .pinnedFloorScrollBoth)
        #expect(after.cellSide == 44)
    }

    // MARK: - (c) Expert 375×500 → pinned branch, floor raised 32 → 44

    @Test("Expert at 375pt width stays pinned-floor; cellSide rises 32 → 44")
    func expertAt375PinnedFloorRaised() {
        let difficulty = Difficulty.expert
        let availW = avail(offered: 375, count: difficulty.columns)
        let availH = avail(offered: 500, count: difficulty.rows)

        let before = MinesweeperBoardView.cellSizing(
            availW: availW, availH: availH,
            rows: difficulty.rows, cols: difficulty.columns,
            floor: 32 // pre-#764 shared floor
        )
        let after = MinesweeperBoardView.cellSizing(
            availW: availW, availH: availH,
            rows: difficulty.rows, cols: difficulty.columns,
            floor: MinesweeperBoardView.minCellSide(for: difficulty)
        )

        #expect(before.branch == .pinnedFloorScrollBoth)
        #expect(before.cellSide == 32)
        #expect(after.branch == .pinnedFloorScrollBoth)
        #expect(after.cellSide == 44)
    }

    // MARK: - (d) Middle branch (heightFit) still reachable — no regression

    @Test("Intermediate with tall offered height uses the heightFit scroll-horizontal branch")
    func intermediateTallHeightUsesHeightFitBranch() {
        let difficulty = Difficulty.intermediate
        let sizing = MinesweeperBoardView.cellSizing(
            availW: avail(offered: 375, count: difficulty.columns),
            availH: avail(offered: 900, count: difficulty.rows),
            rows: difficulty.rows,
            cols: difficulty.columns,
            floor: MinesweeperBoardView.minCellSide(for: difficulty)
        )
        #expect(sizing.branch == .heightFitScrollHorizontal)
        #expect(sizing.cellSide == 54)
    }

    // MARK: - 402pt width sanity (iPhone 16 Pro Max-class) — same branch shape

    @Test("Intermediate at 402pt width still lands pinned-floor; cellSide rises 32 → 44")
    func intermediateAt402PinnedFloorRaised() {
        let difficulty = Difficulty.intermediate
        let availW = avail(offered: 402, count: difficulty.columns)
        let availH = avail(offered: 500, count: difficulty.rows)

        let before = MinesweeperBoardView.cellSizing(
            availW: availW, availH: availH,
            rows: difficulty.rows, cols: difficulty.columns,
            floor: 32
        )
        let after = MinesweeperBoardView.cellSizing(
            availW: availW, availH: availH,
            rows: difficulty.rows, cols: difficulty.columns,
            floor: MinesweeperBoardView.minCellSide(for: difficulty)
        )

        #expect(before.branch == .pinnedFloorScrollBoth)
        #expect(before.cellSide == 32)
        #expect(after.branch == .pinnedFloorScrollBoth)
        #expect(after.cellSide == 44)
    }
}
