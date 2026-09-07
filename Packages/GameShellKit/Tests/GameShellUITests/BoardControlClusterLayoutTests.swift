// BoardControlClusterLayoutTests — design.md §7's hard rule, asserted.
//
// "**G4 不得覆蓋任何可互動格子** —— 這是版面規則,幾何不隨開關改變,**必須以最壞
// 情況(IC+RT)為設計基準**" (§7).
//
// A screenshot cannot establish this: it shows one width, one text size and one
// accessibility combination. What follows sweeps the three breakpoint widths
// from §3.4's cell table against cluster heights from "no cluster at all" up
// past anything the `.xLarge`-capped controls can render, and asserts the rule
// survives every one of them.
//
// Why nothing here sweeps the eight Reduce Motion × Increase Contrast × Reduce
// Transparency combinations §7 enumerates: `bands(...)` takes no accessibility
// input, because those switches change how the glass is PAINTED and painting is
// not layout. Sampling them would be sampling the same call eight times. What
// CAN legitimately grow the cluster is Dynamic Type, so that is what the sweeps
// below vary — and they run past anything the `.xLarge` cap (#540) can render,
// which is what "以最壞情況為設計基準" asks for.
//
// The banner slot is not modelled. It only ever adds chrome above the cluster,
// and the property being pinned ("the board yields, the cluster never
// encroaches") is monotonic in total chrome height, so the height sweeps
// already cover the board-with-banner case.

import CoreGraphics
import Testing
@testable import GameShellUI

@Suite("BoardControlClusterLayout — §7: G4 never covers an interactive cell")
struct BoardControlClusterLayoutTests {

    /// §3.4's three cell-size breakpoints, as screen widths.
    private static let breakpointWidths: [CGFloat] = [320, 393, 430]
    /// Heights those devices actually offer, paired with the widths above.
    private static let breakpointHeights: [CGFloat] = [568, 852, 932]

    private static func bands(
        width: CGFloat,
        height: CGFloat,
        editGroupHeight: CGFloat?,
        inputGroupHeight: CGFloat
    ) -> BoardControlClusterLayout.Bands {
        BoardControlClusterLayout.bands(
            offered: CGSize(width: width, height: height),
            verticalMargin: 16,
            headerHeight: 44,
            stackSpacing: 16,
            editGroupHeight: editGroupHeight,
            inputGroupHeight: inputGroupHeight,
            groupSpacing: 8
        )
    }

    // MARK: - The hard rule

    @Test("No glass group intersects any cell, at every breakpoint × cluster height")
    func noGlassGroupIntersectsACell() {
        // 44…260 spans an edit row alone through a 3×3 digit grid inflated well
        // past what the `.xLarge` Dynamic Type cap (#540) can produce.
        for inputHeight in stride(from: 44.0, through: 260.0, by: 12.0) {
            for (width, height) in zip(Self.breakpointWidths, Self.breakpointHeights) {
                let bands = Self.bands(
                    width: width,
                    height: height,
                    editGroupHeight: 44,
                    inputGroupHeight: inputHeight
                )
                let cells = BoardControlClusterLayout.cellRects(in: bands.board, rows: 9, columns: 9)
                #expect(!cells.isEmpty)
                for group in bands.glassGroups {
                    for cell in cells {
                        #expect(
                            !cell.intersects(group),
                            """
                            G4 covered a cell at width \(width), input height \(inputHeight): \
                            cell \(cell) intersects group \(group)
                            """
                        )
                    }
                }
            }
        }
    }

    @Test("The rule holds for Minesweeper's non-square boards too")
    func noGlassGroupIntersectsACellOnMinesweeperBoards() {
        // Beginner 9×9, Intermediate 16×16, Expert 16×30 (rows × columns).
        let boards = [(9, 9), (16, 16), (16, 30)]
        for (rows, columns) in boards {
            for (width, height) in zip(Self.breakpointWidths, Self.breakpointHeights) {
                // MS ships a single populated group today (#1052).
                let bands = Self.bands(
                    width: width,
                    height: height,
                    editGroupHeight: nil,
                    inputGroupHeight: 44
                )
                let cells = BoardControlClusterLayout.cellRects(in: bands.board, rows: rows, columns: columns)
                for cell in cells {
                    #expect(!cell.intersects(bands.inputGroup))
                }
            }
        }
    }

    @Test("A taller cluster shrinks the board — it never encroaches on it")
    func theBoardYieldsSpaceNotTheCluster() {
        var previousBoardSide = CGFloat.greatestFiniteMagnitude
        for inputHeight in stride(from: 44.0, through: 400.0, by: 20.0) {
            let bands = Self.bands(
                width: 393,
                height: 852,
                editGroupHeight: 44,
                inputGroupHeight: inputHeight
            )
            #expect(bands.board.height <= previousBoardSide)
            #expect(bands.board.maxY <= bands.glassGroups.map(\.minY).min() ?? 0)
            previousBoardSide = bands.board.height
        }
        // Even an absurd cluster only drives the board to zero, never negative
        // (a negative side would flip the rect and silently pass `intersects`).
        let crushed = Self.bands(width: 393, height: 852, editGroupHeight: 44, inputGroupHeight: 4000)
        #expect(crushed.board.height == 0)
    }

    // MARK: - Two groups, never one

    @Test("The two glass groups are disjoint bands, never one merged surface")
    func theTwoGroupsAreDisjoint() throws {
        for (width, height) in zip(Self.breakpointWidths, Self.breakpointHeights) {
            let bands = Self.bands(width: width, height: height, editGroupHeight: 44, inputGroupHeight: 184)
            let edit = try #require(bands.editGroup)
            #expect(!edit.intersects(bands.inputGroup))
            #expect(bands.glassGroups.count == 2)
        }
    }

    @Test("A single-group cluster reports one group, not an empty second one")
    func singleGroupClusterHasNoEmptyEditBand() {
        let bands = Self.bands(width: 393, height: 852, editGroupHeight: nil, inputGroupHeight: 44)
        #expect(bands.editGroup == nil)
        #expect(bands.glassGroups.count == 1)
    }

    // MARK: - Full-bleed cell side (design.md §3.4's table)

    @Test("Full-bleed cell side is the screen width / 9, with no inset")
    func fullBleedCellSideMatchesTheTable() {
        // §3.4's table quotes 35.1 / 43.2 / 47.3, derived as (W − 4) / 9 — it
        // deducts a 4pt outer frame ("扣除外框", 附錄 B). This board has no such
        // frame (only per-cell hairlines), so the real full-bleed side is W / 9,
        // which lands at or above every figure in the table. See #1022's PR body.
        let expected: [CGFloat] = [320.0 / 9, 393.0 / 9, 430.0 / 9]
        for (width, side) in zip(Self.breakpointWidths, expected) {
            #expect(BoardControlClusterLayout.fullBleedCellSide(screenWidth: width, columns: 9) == side)
            #expect(side >= (width - 4) / 9)
        }
    }
}
