// BoardViewRegularContainerTests — pins BoardView's regular-width container
// mapping (#1105), mirroring MinesweeperKit's `RegularBoardContainerTests`
// for the Sudoku-specific numbers (960/640 outer/board caps, center/topLeading
// board alignment).

import GameShellUI
import SwiftUI
import Testing
@testable import SudokuUI

@Suite("BoardView regular-width container (#1105)")
struct BoardViewRegularContainerTests {

    @Test("regularOuterMaxWidth maps cappedDetailPane to 960 and fillsColumn to infinity")
    func regularOuterMaxWidthMapsPerContainer() {
        #expect(BoardView.regularOuterMaxWidth(for: .cappedDetailPane) == 960)
        #expect(BoardView.regularOuterMaxWidth(for: .fillsColumn) == .infinity)
    }

    @Test("regularBoardMaxSide maps cappedDetailPane to 640 and fillsColumn to infinity")
    func regularBoardMaxSideMapsPerContainer() {
        #expect(BoardView.regularBoardMaxSide(for: .cappedDetailPane) == 640)
        #expect(BoardView.regularBoardMaxSide(for: .fillsColumn) == .infinity)
    }

    @Test("regularBoardAlignment maps cappedDetailPane to center and fillsColumn to topLeading")
    func regularBoardAlignmentMapsPerContainer() {
        #expect(BoardView.regularBoardAlignment(for: .cappedDetailPane) == .center)
        #expect(BoardView.regularBoardAlignment(for: .fillsColumn) == .topLeading)
    }
}
