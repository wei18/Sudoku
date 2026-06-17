// GameViewModelAudioTests (#330 P2) — assert the gameplay VM fires the right
// `AudioEvent` at each trigger point, using the order-preserving
// `FakeSoundPlaying`. AVFoundation never enters the test: the VM holds only the
// `SoundPlaying` seam, and the fake records every `play(_:)` synchronously in
// call order.
//
// Trigger points (per the P2 spec):
//   - solving the puzzle           → `.win` exactly once (no place/complete)
//   - an incorrect entry (mistake) → `.error`
//   - completing a row/box/region  → `.complete`
//   - placing a number             → `.place` with NO haptic

import Foundation
import GameAudio
import GameAudioTesting
import SudokuGameState
import Persistence
import PersistenceTesting
import SudokuPersistence
import SudokuEngine
import Testing
@testable import SudokuUI

@MainActor
@Suite("GameViewModel — #330 P2 gameplay audio cues")
struct GameViewModelAudioTests {

    private static let identity = PuzzleIdentity.practice(salt: 7, difficulty: .easy)

    /// A fully-solved canonical Sudoku (valid rows / columns / boxes). Same
    /// string as SudokuCoreKit's `BoardFixtures.solvedKnown`; inlined because
    /// that fixture lives in the engine package's test target. A valid solution
    /// is required so conflict + section-completion detection behave like a real
    /// game (the Latin-square fixture has column conflicts and is unusable here).
    private static let solvedDigits = Array(
        "534678912672195348198342567859761423426853791713924856961537284287419635345286179"
    ).map { Int(String($0)) ?? 0 }

    /// The solution digit at `(row, column)` per `solvedDigits`.
    private func solutionDigit(row: Int, column: Int) -> Int {
        Self.solvedDigits[Board.index(row: row, column: column)]
    }

    /// Build a puzzle from the canonical solved board with `blanks` removed.
    private func makePuzzle(blanks: Set<GridCoordinate>) throws -> Puzzle {
        var solution = Board()
        var cluesString = ""
        for index in 0..<Board.cellCount {
            let digit = Self.solvedDigits[index]
            try solution.setDigit(digit, atIndex: index)
            let coord = GridCoordinate(row: index / 9, column: index % 9)
            cluesString.append(blanks.contains(coord) ? "." : String(digit))
        }
        let clues = try Board(clues: cluesString)
        return Puzzle(clues: clues, solution: solution, difficulty: .easy, generatorVersion: .v1, seed: 0)
    }

    private func makeViewModel(
        blanks: Set<GridCoordinate>,
        sound: FakeSoundPlaying
    ) throws -> GameViewModel {
        let puzzle = try makePuzzle(blanks: blanks)
        let session = GameSession(puzzle: puzzle)
        return GameViewModel(
            identity: Self.identity,
            session: session,
            initialBoard: puzzle.clues,
            initialStatus: .idle,
            persistence: FakePersistence(),
            soundPlayer: sound,
            saveDebounceNanos: 0
        )
    }

    @Test("solving fires .win exactly once")
    func solvingFiresWinOnce() async throws {
        // One empty cell at (0,0) → placing its solution digit solves the board.
        let sound = FakeSoundPlaying()
        let viewModel = try makeViewModel(blanks: [GridCoordinate(row: 0, column: 0)], sound: sound)
        viewModel.selection = GridCoordinate(row: 0, column: 0)
        await viewModel.startOrResume()

        await viewModel.placeDigit(solutionDigit(row: 0, column: 0))

        #expect(viewModel.status == .completed)
        #expect(sound.playedEvents == [.sudokuWin])
        #expect(sound.playedEvents.filter { $0 == .sudokuWin }.count == 1)
    }

    @Test("a mistake fires .error with an error haptic")
    func mistakeFiresError() async throws {
        // Two empties so the wrong digit doesn't also solve the board. Row 0 of
        // the solved board is "534678912"; its solution at (0,0) is 5. Placing
        // 3 (already present at (0,1)) creates a row conflict → mistake.
        let sound = FakeSoundPlaying()
        let blanks: Set<GridCoordinate> = [GridCoordinate(row: 0, column: 0), GridCoordinate(row: 8, column: 8)]
        let viewModel = try makeViewModel(blanks: blanks, sound: sound)
        viewModel.selection = GridCoordinate(row: 0, column: 0)
        await viewModel.startOrResume()

        await viewModel.placeDigit(3)

        #expect(viewModel.status == .playing)
        #expect(sound.playedEvents == [.sudokuMistake])
        #expect(AudioEvent.sudokuMistake.haptic == .error)
    }

    @Test("completing a section fires .complete after .place")
    func sectionClearedFiresComplete() async throws {
        // Blank (0,0) + (4,4): placing (0,0)'s solution digit (5) completes row
        // 0, column 0, and box 0 (all were one-cell-short), but (4,4) keeps the
        // puzzle unsolved → place + complete, no win.
        let sound = FakeSoundPlaying()
        let blanks: Set<GridCoordinate> = [GridCoordinate(row: 0, column: 0), GridCoordinate(row: 4, column: 4)]
        let viewModel = try makeViewModel(blanks: blanks, sound: sound)
        viewModel.selection = GridCoordinate(row: 0, column: 0)
        await viewModel.startOrResume()

        await viewModel.placeDigit(solutionDigit(row: 0, column: 0))

        #expect(viewModel.status == .playing)
        #expect(sound.playedEvents == [.sudokuPlace, .sudokuSectionCleared])
    }

    @Test("placing a number fires .place with NO haptic and no section cue")
    func plainPlaceFiresPlaceNoHaptic() async throws {
        // A 2x2 blank block in box 0 means filling one of its cells completes
        // no row / column / box → a plain placement only.
        let sound = FakeSoundPlaying()
        let blanks: Set<GridCoordinate> = [
            GridCoordinate(row: 0, column: 0), GridCoordinate(row: 0, column: 1),
            GridCoordinate(row: 1, column: 0), GridCoordinate(row: 1, column: 1)
        ]
        let viewModel = try makeViewModel(blanks: blanks, sound: sound)
        viewModel.selection = GridCoordinate(row: 0, column: 1)
        await viewModel.startOrResume()

        await viewModel.placeDigit(solutionDigit(row: 0, column: 1))

        #expect(viewModel.status == .playing)
        #expect(sound.playedEvents == [.sudokuPlace])
        #expect(AudioEvent.sudokuPlace.haptic == nil)
    }
}
