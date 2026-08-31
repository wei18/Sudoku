// SudokuBoardPreviewMapperTests — #1017.
//
// Pure mapping tests: no `.live()`, no CloudKit. Covers the happy path
// (given vs filled vs blank) and the degrade contract (missing/malformed
// input → nil, never a crash).

import Testing
import GameShellUI
import SudokuAppComposition

@Suite("SudokuBoardPreviewMapper")
struct SudokuBoardPreviewMapperTests {

    private static let allGiven = Array(repeating: true, count: 81)
    private static let allBlank = Array(repeating: false, count: 81)

    @Test("maps blank cells to .empty")
    func blankCellsMapToEmpty() throws {
        let boardState = String(repeating: ".", count: 81)
        let preview = try #require(
            SudokuBoardPreviewMapper.make(boardState: boardState, givenMask: Self.allBlank)
        )
        #expect(preview.columns == 9)
        #expect(preview.rows == 9)
        #expect(preview.cells.allSatisfy { $0 == .empty })
    }

    @Test("a digit at a given index maps to .given")
    func givenDigitMapsToGiven() throws {
        let boardState = "5" + String(repeating: ".", count: 80)
        var mask = Self.allBlank
        mask[0] = true
        let preview = try #require(
            SudokuBoardPreviewMapper.make(boardState: boardState, givenMask: mask)
        )
        #expect(preview.cells[0] == .given)
        #expect(preview.cells[1] == .empty)
    }

    @Test("a digit at a non-given index maps to .filled")
    func userEnteredDigitMapsToFilled() throws {
        let boardState = "5" + String(repeating: ".", count: 80)
        let preview = try #require(
            SudokuBoardPreviewMapper.make(boardState: boardState, givenMask: Self.allBlank)
        )
        #expect(preview.cells[0] == .filled)
    }

    @Test("nil boardState degrades to nil preview")
    func nilBoardStateDegradesToNil() {
        #expect(SudokuBoardPreviewMapper.make(boardState: nil, givenMask: Self.allBlank) == nil)
    }

    @Test("truncated boardState degrades to nil preview")
    func truncatedBoardStateDegradesToNil() {
        #expect(SudokuBoardPreviewMapper.make(boardState: "123", givenMask: Self.allBlank) == nil)
    }

    @Test("mismatched givenMask length degrades to nil preview")
    func mismatchedGivenMaskLengthDegradesToNil() {
        let boardState = String(repeating: ".", count: 81)
        #expect(SudokuBoardPreviewMapper.make(boardState: boardState, givenMask: []) == nil)
    }

    @Test("an invalid character degrades to nil preview")
    func invalidCharacterDegradesToNil() {
        let boardState = "x" + String(repeating: ".", count: 80)
        #expect(SudokuBoardPreviewMapper.make(boardState: boardState, givenMask: Self.allBlank) == nil)
    }
}
