import Foundation
import SudokuEngine
import Testing
@testable import GameState

@Suite("GameSession play (placeDigit / note / undo / redo)")
struct GameSessionPlayTests {

    @Test("placeDigit writes the digit to currentBoard")
    func placeDigitWritesToBoard() async throws {
        let session = GameSession(puzzle: TestPuzzles.simple)
        try await session.start()
        try await session.placeDigit(row: 0, col: 1, digit: 5)
        let cell = await session.currentBoard.digit(atRow: 0, column: 1)
        #expect(cell == 5)
    }

    @Test("placeDigit captures previous value (overwrite + undo restores prior)")
    func placeDigitCapturesPreviousValue() async throws {
        let session = GameSession(puzzle: TestPuzzles.simple)
        try await session.start()
        try await session.placeDigit(row: 0, col: 1, digit: 3)
        try await session.placeDigit(row: 0, col: 1, digit: 7)
        try await session.undo()
        let cell = await session.currentBoard.digit(atRow: 0, column: 1)
        #expect(cell == 3, "Undo must restore the prior digit (3), not empty")
    }

    @Test("placeDigit on a clue cell throws cellImmutable")
    func placeDigitOnGivenCellThrows() async throws {
        // TestPuzzles.simple has a clue '1' at (0,0).
        let session = GameSession(puzzle: TestPuzzles.simple)
        try await session.start()
        await #expect(throws: GameSessionError.self) {
            try await session.placeDigit(row: 0, col: 0, digit: 9)
        }
    }

    @Test("placeDigit while not playing throws invalidStateForAction")
    func placeDigitWhenNotPlayingThrows() async {
        let session = GameSession(puzzle: TestPuzzles.simple)
        // status == .idle
        await #expect(throws: GameSessionError.self) {
            try await session.placeDigit(row: 0, col: 1, digit: 5)
        }
    }

    @Test("toggleNote adds then removes a candidate")
    func toggleNoteFlipsBit() async throws {
        let session = GameSession(puzzle: TestPuzzles.simple)
        try await session.start()
        try await session.toggleNote(row: 1, col: 1, digit: 4)
        var contains = await session.notes.contains(digit: 4, row: 1, col: 1)
        #expect(contains == true)
        try await session.toggleNote(row: 1, col: 1, digit: 4)
        contains = await session.notes.contains(digit: 4, row: 1, col: 1)
        #expect(contains == false)
    }

    @Test("undo three times returns to clue-only board")
    func undoRestoresPreviousBoard() async throws {
        let session = GameSession(puzzle: TestPuzzles.simple)
        try await session.start()
        try await session.placeDigit(row: 0, col: 1, digit: 1)
        try await session.placeDigit(row: 0, col: 2, digit: 2)
        try await session.placeDigit(row: 0, col: 3, digit: 3)
        try await session.undo()
        try await session.undo()
        try await session.undo()
        let board = await session.currentBoard
        #expect(board.encoded() == TestPuzzles.simple.clues.encoded())
    }

    @Test("redo reapplies an undone move")
    func redoReappliesMove() async throws {
        let session = GameSession(puzzle: TestPuzzles.simple)
        try await session.start()
        try await session.placeDigit(row: 0, col: 1, digit: 6)
        try await session.undo()
        try await session.redo()
        let cell = await session.currentBoard.digit(atRow: 0, column: 1)
        #expect(cell == 6)
    }

    @Test("placeDigit emits digitPlaced telemetry event")
    func placeDigitEmitsTelemetry() async throws {
        let spy = SpyTelemetry()
        let session = GameSession(puzzle: TestPuzzles.simple, telemetry: spy)
        try await session.start()
        try await session.placeDigit(row: 0, col: 1, digit: 5)
        let events = await spy.events
        #expect(events.contains(.digitPlaced(row: 0, col: 1, digit: 5, previous: nil)))
    }

    @Test("Completion is sticky: undo after auto-complete does not reopen")
    func completionIsSticky() async throws {
        // Build a near-solved puzzle where filling one specific cell completes.
        let puzzle = TestPuzzles.nearSolved(missingRow: 0, missingCol: 0)
        let session = GameSession(puzzle: puzzle)
        try await session.start()
        try await session.placeDigit(
            row: 0,
            col: 0,
            digit: Int(puzzle.solution.cells[Board.index(row: 0, column: 0)])
        )
        let status = await session.status
        #expect(status == .completed)
        // Now undo would require .playing — must throw (or be a no-op).
        await #expect(throws: GameSessionError.self) {
            try await session.undo()
        }
    }
}

// Test-only spy implementing the local GameStateTelemetry seam.
actor SpyTelemetry: GameStateTelemetry {
    private(set) var events: [GameStateEvent] = []
    func dispatch(_ event: GameStateEvent) async {
        events.append(event)
    }
}

extension TestPuzzles {
    /// A puzzle whose `clues` differ from `solution` only at the one given
    /// (missingRow, missingCol) cell — placing the correct digit there
    /// completes the board.
    static func nearSolved(missingRow: Int, missingCol: Int) -> Puzzle {
        var solution = Board()
        for index in 0..<Board.cellCount {
            // Simple "shifted row" Latin square — not Sudoku-valid but
            // matches itself, which is all completion-detection needs.
            // swiftlint:disable:next force_try
            try! solution.setDigit(((index % 9) + 1), atIndex: index)
        }
        var cluesString = ""
        for index in 0..<Board.cellCount {
            let row = index / 9
            let col = index % 9
            if row == missingRow && col == missingCol {
                cluesString.append(".")
            } else {
                let digit = (index % 9) + 1
                cluesString.append(String(digit))
            }
        }
        // swiftlint:disable:next force_try
        let clues = try! Board(clues: cluesString)
        return Puzzle(
            clues: clues,
            solution: solution,
            difficulty: .easy,
            generatorVersion: .v1,
            seed: 0
        )
    }
}
