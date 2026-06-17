import Foundation
import SudokuEngine
import Testing
 import SudokuGameState

@Suite("GameSession lifecycle transitions")
struct GameSessionTransitionTests {

    @Test("New session starts in .idle and surfaces clue board")
    func freshSessionIsIdle() async {
        let session = GameSession(puzzle: TestPuzzles.simple)
        await #expect(session.status == .idle)
        await #expect(session.currentBoard.encoded() == TestPuzzles.simple.clues.encoded())
    }

    @Test("start() takes idle to playing")
    func startIdleToPlaying() async throws {
        let session = GameSession(puzzle: TestPuzzles.simple)
        try await session.start()
        await #expect(session.status == .playing)
    }

    @Test("start() from non-idle throws illegalTransition")
    func startFromPlayingThrows() async throws {
        let session = GameSession(puzzle: TestPuzzles.simple)
        try await session.start()
        await #expect(throws: GameSessionError.self) {
            try await session.start()
        }
    }

    @Test("pause() takes playing to paused; paused→pause throws")
    func pauseFlow() async throws {
        let session = GameSession(puzzle: TestPuzzles.simple)
        try await session.start()
        try await session.pause()
        await #expect(session.status == .paused)
        await #expect(throws: GameSessionError.self) {
            try await session.pause()
        }
    }

    @Test("resume() takes paused to playing")
    func resumeFlow() async throws {
        let session = GameSession(puzzle: TestPuzzles.simple)
        try await session.start()
        try await session.pause()
        try await session.resume()
        await #expect(session.status == .playing)
    }

    @Test("complete() takes playing to completed (sticky on second call)")
    func completeFlow() async throws {
        let session = GameSession(puzzle: TestPuzzles.simple)
        try await session.start()
        try await session.complete()
        await #expect(session.status == .completed)
        // Completion is sticky: completing again throws (illegal transition).
        await #expect(throws: GameSessionError.self) {
            try await session.complete()
        }
    }

    @Test("abandon() works from playing and from paused")
    func abandonFromPlaying() async throws {
        let session = GameSession(puzzle: TestPuzzles.simple)
        try await session.start()
        try await session.abandon()
        await #expect(session.status == .abandoned)

        let session2 = GameSession(puzzle: TestPuzzles.simple)
        try await session2.start()
        try await session2.pause()
        try await session2.abandon()
        await #expect(session2.status == .abandoned)
    }

    @Test("abandon() from idle throws")
    func abandonFromIdleThrows() async {
        let session = GameSession(puzzle: TestPuzzles.simple)
        await #expect(throws: GameSessionError.self) {
            try await session.abandon()
        }
    }

    @Test("illegalTransition error carries from/applying")
    func errorCarriesContext() async {
        let session = GameSession(puzzle: TestPuzzles.simple)
        do {
            try await session.pause()
            Issue.record("Expected throw")
        } catch let error as GameSessionError {
            #expect(error == .illegalTransition(from: .idle, applying: .pause))
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }
}

// Shared test fixtures local to GameStateTests (Phase 3 has no shared helper module yet).
enum TestPuzzles {
    static let simple: Puzzle = make()

    private static func make() -> Puzzle {
        // 81-char board with one clue '1' at (0,0) — sufficient for transition tests.
        let cluesEncoded = "1" + String(repeating: ".", count: 80)
        // swiftlint:disable:next force_try
        let clues = try! Board(clues: cluesEncoded)
        // The "solution" doesn't need to actually be a valid Sudoku for transition
        // tests — completion-detection tests fabricate their own boards.
        var solution = Board()
        for index in 0..<Board.cellCount {
            // swiftlint:disable:next force_try
            try! solution.setDigit(((index % 9) + 1), atIndex: index)
        }
        return Puzzle(
            clues: clues,
            solution: solution,
            difficulty: .easy,
            generatorVersion: .v1,
            seed: 0
        )
    }
}
