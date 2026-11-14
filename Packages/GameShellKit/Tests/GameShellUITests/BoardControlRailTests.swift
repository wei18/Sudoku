// BoardControlRailTests — #1114: the key-size arithmetic ties every key grid
// on the rail to the one shared rail width.

import CoreGraphics
import Testing
@testable import GameShellUI

@Suite("BoardControlRail — key grid fits the shared rail (#1114)")
struct BoardControlRailTests {

    @Test("columns of keyWidth plus spacing fill the rail exactly")
    func keysFillRail() {
        let columns = 3
        let total = CGFloat(columns) * BoardControlRail.keyWidth(columns: columns)
            + CGFloat(columns - 1) * BoardControlRail.keyGridSpacing
        #expect(abs(total - BoardControlRail.width) < 0.001)
    }

    @Test("minimum labels with the widest chrome never exceed the rail")
    func minimumLabelsFit() {
        let columns = 3
        let keyMin = BoardControlRail.keyLabelMinWidth(columns: columns)
            + 2 * BoardControlRail.widestButtonChromeInset
        let total = CGFloat(columns) * keyMin
            + CGFloat(columns - 1) * BoardControlRail.keyGridSpacing
        #expect(total <= BoardControlRail.width)
    }

    @Test("three-column label minimum is 57")
    func threeColumnLabelMinimum() {
        #expect(BoardControlRail.keyLabelMinWidth(columns: 3) == 57)
    }
}
