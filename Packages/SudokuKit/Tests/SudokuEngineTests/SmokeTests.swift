import Testing
@testable import SudokuEngine

@Suite("SudokuEngine smoke")
struct SudokuEngineSmokeTests {
    @Test func packageCompiles() {
        moduleAnchor()
    }
}
