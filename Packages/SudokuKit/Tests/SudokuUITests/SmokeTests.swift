import Testing
@testable import SudokuUI

@Suite("SudokuUI smoke")
struct SudokuUISmokeTests {
    @Test func packageCompiles() {
        _moduleAnchor()
    }
}
