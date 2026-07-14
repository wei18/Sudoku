// MinesweeperBoardZoomTests — #815: pinch-to-zoom scale clamping + the
// resulting cell-side derivation. `MinesweeperBoardView.clampZoomScale` and
// `.zoomedCellSide(baseCellSide:zoomScale:)` are the pure helpers extracted
// from the pinch gesture so this logic can be pinned without hosting a
// SwiftUI view or driving a real `MagnifyGesture` (see
// `MinesweeperBoardCellSizingTests` for the sibling #764 ladder suite this
// mirrors in shape).

import Foundation
import Testing
@testable import MinesweeperUI

@Suite("MinesweeperBoardView zoom — scale clamp + cellSide derivation (#815)")
struct MinesweeperBoardZoomTests {

    // MARK: - Range constants

    @Test("Zoom range is 0.5x–2.0x")
    func zoomRangeConstants() {
        #expect(MinesweeperBoardView.minZoomScale == 0.5)
        #expect(MinesweeperBoardView.maxZoomScale == 2.0)
    }

    // MARK: - clampZoomScale

    @Test("Scale within range passes through unchanged")
    func clampWithinRangeUnchanged() {
        #expect(MinesweeperBoardView.clampZoomScale(1.0) == 1.0)
        #expect(MinesweeperBoardView.clampZoomScale(0.75) == 0.75)
        #expect(MinesweeperBoardView.clampZoomScale(1.5) == 1.5)
    }

    @Test("Scale below the floor clamps to minZoomScale")
    func clampBelowFloor() {
        #expect(MinesweeperBoardView.clampZoomScale(0.1) == MinesweeperBoardView.minZoomScale)
        #expect(MinesweeperBoardView.clampZoomScale(0) == MinesweeperBoardView.minZoomScale)
        #expect(MinesweeperBoardView.clampZoomScale(-3) == MinesweeperBoardView.minZoomScale)
    }

    @Test("Scale above the ceiling clamps to maxZoomScale")
    func clampAboveCeiling() {
        #expect(MinesweeperBoardView.clampZoomScale(2.01) == MinesweeperBoardView.maxZoomScale)
        #expect(MinesweeperBoardView.clampZoomScale(10) == MinesweeperBoardView.maxZoomScale)
    }

    @Test("Range boundaries are inclusive")
    func clampBoundariesInclusive() {
        #expect(MinesweeperBoardView.clampZoomScale(0.5) == 0.5)
        #expect(MinesweeperBoardView.clampZoomScale(2.0) == 2.0)
    }

    // MARK: - zoomedCellSide

    @Test("1.0x zoom returns the base cell side, floored")
    func zoomedCellSideIdentityAtOne() {
        #expect(MinesweeperBoardView.zoomedCellSide(baseCellSide: 44, zoomScale: 1.0) == 44)
    }

    @Test("2.0x zoom doubles the base cell side")
    func zoomedCellSideDoublesAtMax() {
        #expect(MinesweeperBoardView.zoomedCellSide(baseCellSide: 44, zoomScale: 2.0) == 88)
    }

    @Test("0.5x zoom halves the base cell side")
    func zoomedCellSideHalvesAtMin() {
        #expect(MinesweeperBoardView.zoomedCellSide(baseCellSide: 44, zoomScale: 0.5) == 22)
    }

    @Test("An out-of-range zoomScale is clamped before being applied")
    func zoomedCellSideClampsOutOfRangeInput() {
        // 5.0x is above maxZoomScale (2.0) — must clamp to 2.0x, not apply 5x raw.
        #expect(MinesweeperBoardView.zoomedCellSide(baseCellSide: 44, zoomScale: 5.0) == 88)
        // 0.01x is below minZoomScale (0.5) — must clamp to 0.5x.
        #expect(MinesweeperBoardView.zoomedCellSide(baseCellSide: 44, zoomScale: 0.01) == 22)
    }

    @Test("Non-integer results are floored, mirroring cellSizing's own flooring")
    func zoomedCellSideFloorsFractionalResult() {
        // 39 * 1.5 = 58.5 → floors to 58.
        #expect(MinesweeperBoardView.zoomedCellSide(baseCellSide: 39, zoomScale: 1.5) == 58)
    }
}
