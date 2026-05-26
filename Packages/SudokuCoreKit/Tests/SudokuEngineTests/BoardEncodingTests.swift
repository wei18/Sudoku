import Foundation
import Testing
@testable import SudokuEngine

@Suite("BoardEncoding")
struct BoardEncodingTests {

    @Test func roundtripEmptyBoard() throws {
        let encoded = String(repeating: ".", count: 81)
        let board = try Board(clues: encoded)
        #expect(board.encoded() == encoded)
        #expect(board.givens().isEmpty)
        #expect(board.isFullyFilled == false)
    }

    @Test func roundtripFullBoard() throws {
        // A valid, fully-filled Sudoku (canonical example).
        let solved = "534678912672195348198342567859761423426853791713924856961537284287419635345286179"
        let board = try Board(clues: solved)
        #expect(board.encoded() == solved)
        #expect(board.givens().count == 81)
        #expect(board.isFullyFilled)
    }

    @Test func roundtripZeroSyntaxEmptyCells() throws {
        // '0' may also represent empty.
        let mixed = "530070000600195000098000060800060003400803001700020006060000280000419005000080079"
        let board = try Board(clues: mixed)
        // encoded() normalizes to '.'.
        let expected = mixed.replacingOccurrences(of: "0", with: ".")
        #expect(board.encoded() == expected)
    }

    @Test func rejectMalformedLength() {
        let tooShort = String(repeating: ".", count: 80)
        #expect(throws: BoardError.self) {
            _ = try Board(clues: tooShort)
        }
        let tooLong = String(repeating: ".", count: 82)
        #expect(throws: BoardError.self) {
            _ = try Board(clues: tooLong)
        }
    }

    @Test func rejectMalformedCharacter() {
        var encoded = String(repeating: ".", count: 81)
        let idx = encoded.index(encoded.startIndex, offsetBy: 5)
        encoded.replaceSubrange(idx...idx, with: "X")
        #expect(throws: BoardError.self) {
            _ = try Board(clues: encoded)
        }
    }

    @Test func cellAccessByRowCol() throws {
        let solved = "534678912672195348198342567859761423426853791713924856961537284287419635345286179"
        let board = try Board(clues: solved)
        #expect(board.digit(atRow: 0, column: 0) == 5)
        #expect(board.digit(atRow: 8, column: 8) == 9)
        #expect(board.digit(atRow: -1, column: 0) == nil)
        #expect(board.digit(atRow: 0, column: 9) == nil)
    }

    @Test func emptyCellReturnsNilDigit() throws {
        let mixed = "53..7....6..195....98....6.8...6...34..8.3..17...2...6.6....28....419..5....8..79"
        let board = try Board(clues: mixed)
        #expect(board.digit(atRow: 0, column: 2) == nil)
        #expect(board.digit(atRow: 0, column: 0) == 5)
    }

    @Test func givensReportClueCells() throws {
        let mixed = "53..7....6..195....98....6.8...6...34..8.3..17...2...6.6....28....419..5....8..79"
        let board = try Board(clues: mixed)
        let givens = Set(board.givens())
        #expect(givens.contains(Board.index(row: 0, column: 0)))   // '5'
        #expect(!givens.contains(Board.index(row: 0, column: 2)))  // '.'
        #expect(givens.count == 30) // count non-'.' chars
    }

    @Test func setDigitUpdatesCellWithoutChangingGivens() throws {
        let mixed = "53..7....6..195....98....6.8...6...34..8.3..17...2...6.6....28....419..5....8..79"
        var board = try Board(clues: mixed)
        let givensBefore = board.givens()
        try board.setDigit(4, atRow: 0, column: 2)
        #expect(board.digit(atRow: 0, column: 2) == 4)
        #expect(board.givens() == givensBefore)
        try board.setDigit(nil, atRow: 0, column: 2)
        #expect(board.digit(atRow: 0, column: 2) == nil)
    }
}
