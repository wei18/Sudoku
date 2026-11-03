// BoardViewRegularContainerTests — pins BoardView's regular-width container
// mapping (#1105), mirroring MinesweeperKit's `RegularBoardContainerTests`
// for the Sudoku-specific numbers (960/640 outer/board caps, center/leading
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

    @Test("regularBoardMaxWidth maps cappedDetailPane to 640 and fillsColumn to infinity")
    func regularBoardMaxWidthMapsPerContainer() {
        #expect(BoardView.regularBoardMaxWidth(for: .cappedDetailPane) == 640)
        #expect(BoardView.regularBoardMaxWidth(for: .fillsColumn) == .infinity)
    }

    @Test("regularBoardMaxHeight maps cappedDetailPane to 640 and fillsColumn to nil")
    func regularBoardMaxHeightMapsPerContainer() {
        #expect(BoardView.regularBoardMaxHeight(for: .cappedDetailPane) == 640)
        #expect(BoardView.regularBoardMaxHeight(for: .fillsColumn) == nil)
    }

    @Test("regularBoardAlignment maps cappedDetailPane to center and fillsColumn to leading")
    func regularBoardAlignmentMapsPerContainer() {
        #expect(BoardView.regularBoardAlignment(for: .cappedDetailPane) == .center)
        #expect(BoardView.regularBoardAlignment(for: .fillsColumn) == .leading)
    }
}
