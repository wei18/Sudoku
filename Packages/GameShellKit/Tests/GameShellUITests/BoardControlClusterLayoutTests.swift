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
            // header | board | cluster — the arrangement both compact layouts
            // build when no banner is showing. The banner adds one more gap and
            // only shrinks the board, which the height sweeps already cover.
            stackGapCount: 2,
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

    // MARK: - Empirical anchor

    // Without this, the suite is self-consistent algebra: `boardSide` and the
    // board band are the same quantity restated, so `board.maxY <= clusterTop`
    // holds for ANY inputs and cannot fail. These are real frames read off a
    // running app — iPhone 17 Pro, Sudoku Debug build of this branch, captured
    // with `idb ui describe-all` (#1022's PR evidence) — so the model is
    // checked against something outside itself.
    //
    // It has already earned its keep once: fed the measured chrome WITHOUT
    // safe-area terms the model predicted a 402pt board where the device
    // renders 392.5pt. Adding `safeAreaTop`/`safeAreaBottom` brought the
    // cluster's top to the measured 539.0 exactly and the board to within
    // 4.5pt. That residual is real and not fudged: the header's rendered
    // height is not exactly the 44pt nominal fed here, and the board centres
    // inside its band, so a few points of slack land in the square rather than
    // the gaps. The tolerance is set to 6pt — tight enough that a genuine
    // layout regression (a re-introduced 16pt inset moves the board by 32)
    // fails it, loose enough not to break on a 1pt metric change.

    private enum Measured {
        static let screen = CGSize(width: 402, height: 874)
        static let board = CGRect(x: 4.75, y: 137.75, width: 392.5, height: 392.5)
        static let editGroup = CGRect(x: 16, y: 539, width: 370, height: 58)
        static let inputGroup = CGRect(x: 16, y: 598, width: 370, height: 226)
        static let safeAreaTop: CGFloat = 59
        static let safeAreaBottom: CGFloat = 34
        static let headerHeight: CGFloat = 44
        static let groupSpacing = inputGroup.minY - editGroup.maxY
    }

    @Test("The measured on-device frames are themselves disjoint")
    func measuredDeviceFramesAreDisjoint() {
        let cells = BoardControlClusterLayout.cellRects(in: Measured.board, rows: 9, columns: 9)
        #expect(cells.count == 81)
        for cell in cells {
            #expect(!cell.intersects(Measured.editGroup))
            #expect(!cell.intersects(Measured.inputGroup))
        }
        #expect(!Measured.editGroup.intersects(Measured.inputGroup))
        // Cell PITCH — the board extent divided by 9 — is 43.61pt. Note this
        // is NOT the 44.17pt that `idb ui describe-all` reports as each cell's
        // frame width: the reported hit rects are ~0.55pt wider than the pitch
        // and therefore overlap slightly, which is fine for touch targets but
        // makes the AX number the wrong one to quote as "the cell size".
        // 43.61 clears §3.4's 43.2 figure and sits just under the HIG 44pt
        // default, exactly as §3.4's ruling anticipates.
        #expect(abs(cells[0].width - 43.61) < 0.05)
        // …and that measured pitch clears §3.4's figure for this device class
        // (43.2pt). This is the comparison that carries meaning: it is the
        // board the device actually rendered, not a restatement of W/9. Note
        // §3.4 itself predicts this class does NOT reach the HIG 44pt default
        // ("仍未達,差距 3.9→0.8pt"); only Pro Max does ("首次跨過").
        #expect(cells[0].width > 43.2)
        #expect(cells[0].width < 44)
        // And a second honest point the measurement forces: on a real 402pt
        // device the board spans 392.5, NOT 402 — a 4.75pt gap each side. The
        // layout applies no horizontal inset (that is what #1022 removed), but
        // with real safe areas the square is still bound by HEIGHT by ~9.5pt,
        // so it stops short of the edges. "Full-bleed" describes the layout
        // rule, not a guarantee that every device renders edge-to-edge.
        #expect(Measured.board.minX > 0)
        #expect(Measured.board.width < Measured.screen.width)
    }

    @Test("The model reproduces the measured device layout")
    func modelMatchesMeasuredDeviceLayout() {
        let bands = BoardControlClusterLayout.bands(
            offered: Measured.screen,
            verticalMargin: 16,
            headerHeight: Measured.headerHeight,
            stackSpacing: 16,
            stackGapCount: 2,
            safeAreaTop: Measured.safeAreaTop,
            safeAreaBottom: Measured.safeAreaBottom,
            editGroupHeight: Measured.editGroup.height,
            inputGroupHeight: Measured.inputGroup.height,
            groupSpacing: Measured.groupSpacing
        )
        // The cluster's top is a hard prediction — no tolerance needed.
        #expect(bands.editGroup?.minY == Measured.editGroup.minY)
        // The board side carries the documented residual.
        #expect(abs(bands.board.width - Measured.board.width) <= 6)
        // Ordering must match reality, not merely be internally consistent.
        #expect(bands.board.maxY <= Measured.editGroup.minY)
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

    /// Pins the helper's contract only — `fullBleedCellSide` is a pure function
    /// of width, so this is an identity and is labelled as one. It CANNOT catch
    /// a re-introduced board inset: the app's real cell size is checked against
    /// §3.4's table in `measuredDeviceFramesAreDisjoint`, on the measured
    /// device geometry, which is the only place that comparison means anything.
    @Test("Full-bleed cell side is the screen width / 9, with no inset")
    func fullBleedCellSideIsWidthOverColumns() {
        for width in Self.breakpointWidths {
            #expect(
                BoardControlClusterLayout.fullBleedCellSide(screenWidth: width, columns: 9) == width / 9
            )
        }
    }
}
