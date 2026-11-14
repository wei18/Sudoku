// DigitPadRailFitTests — #1114: pins Sudoku's ACTUAL digit-label minimum to
// the shared rail width. Arithmetic on purpose: `swift test` renders with
// macOS button metrics (~5 pt glass padding per side), so no render on this
// host can see the iPad overhang (12 pt per side).

import CoreGraphics
import GameShellUI
import Testing
@testable import SudokuUI

@Suite("DigitPadView — Mac/iPad digit grid fits the shared rail (#1114)")
struct DigitPadRailFitTests {

    @Test func digitGridWithWidestChromeFitsRail() {
        let columns = CGFloat(DigitPadView.macDigitColumns)
        let total = columns
            * (DigitPadView.macDigitLabelMinWidth + 2 * BoardControlRail.widestButtonChromeInset)
            + (columns - 1) * BoardControlRail.keyGridSpacing
        #expect(total <= BoardControlRail.width)
    }
}
