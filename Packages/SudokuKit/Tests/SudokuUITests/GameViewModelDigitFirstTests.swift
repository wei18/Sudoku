// GameViewModelDigitFirstTests — digit-first input (#722): arming a digit
// with no cell selected, then placing it via consecutive board-cell taps.
//
// Spec: issue #722 (owner UX proposal, implicit dual-mode, no settings toggle).
// #939 extended the spec to "sticky armed": a board-cell tap never disarms —
// see the tests below tagged #939.

import Foundation
import GameAudio
import GameAudioTesting
import SudokuGameState
import Persistence
import PersistenceTesting
import SudokuPersistence
import SudokuEngine
import SudokuKitTesting
import Testing
@testable import SudokuUI

@MainActor
@Suite("GameViewModel — digit-first input (#722)")
struct GameViewModelDigitFirstTests {

    // latinSquarePuzzle(missingRow: 0, missingCol: 0) has every cell as a
    // given EXCEPT (0,0), whose solution digit is 1. (0,1) is a given
    // holding digit 2.
    private static let emptyRow = 0
    private static let emptyCol = 0
    private static let emptyDigit = 1
    private static let givenRow = 0
    private static let givenCol = 1

    private static let identity = PuzzleIdentity.practice(salt: 9, difficulty: .easy)

    private func makeLiveViewModel() throws -> (GameViewModel, GameSession) {
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        let session = GameSession(puzzle: puzzle)
        let viewModel = GameViewModel(
            identity: Self.identity,
            session: session,
            initialBoard: puzzle.clues,
            initialStatus: .idle,
            persistence: FakePersistence(),
            saveDebounceNanos: 0
        )
        return (viewModel, session)
    }

    /// #939: same fixture as `makeLiveViewModel`, but wired to a
    /// `FakeSoundPlaying` so a test can assert the sticky-armed mismatch
    /// haptic fired.
    private func makeLiveViewModelWithSound() throws -> (GameViewModel, FakeSoundPlaying) {
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        let session = GameSession(puzzle: puzzle)
        let sound = FakeSoundPlaying()
        let viewModel = GameViewModel(
            identity: Self.identity,
            session: session,
            initialBoard: puzzle.clues,
            initialStatus: .idle,
            persistence: FakePersistence(),
            soundPlayer: sound,
            saveDebounceNanos: 0
        )
        return (viewModel, sound)
    }

    // MARK: - arm / disarm toggle

    @Test func keypadDigit_noSelection_armsDigit() async throws {
        let (viewModel, _) = try makeLiveViewModel()
        #expect(viewModel.armedDigit == nil)

        await viewModel.keypadDigit(5)

        #expect(viewModel.armedDigit == 5)
    }

    @Test func keypadDigit_sameDigitAgain_disarms() async throws {
        let (viewModel, _) = try makeLiveViewModel()
        await viewModel.keypadDigit(5)
        #expect(viewModel.armedDigit == 5)

        await viewModel.keypadDigit(5)

        #expect(viewModel.armedDigit == nil)
    }

    @Test func keypadDigit_differentDigit_rearms() async throws {
        let (viewModel, _) = try makeLiveViewModel()
        await viewModel.keypadDigit(5)

        await viewModel.keypadDigit(7)

        #expect(viewModel.armedDigit == 7)
    }

    // MARK: - arm → tap empty cell places and stays armed

    @Test func tapCell_armedOnEmptyCell_placesAndStaysArmed() async throws {
        let (viewModel, _) = try makeLiveViewModel()
        await viewModel.startOrResume()
        await viewModel.keypadDigit(Self.emptyDigit)
        #expect(viewModel.armedDigit == Self.emptyDigit)

        await viewModel.tapCell(row: Self.emptyRow, column: Self.emptyCol)

        #expect(viewModel.board.digit(atRow: Self.emptyRow, column: Self.emptyCol) == Self.emptyDigit,
            "Tapping an empty cell while armed must place the armed digit")
        #expect(viewModel.armedDigit == Self.emptyDigit,
            "The digit must stay armed after a placement for consecutive taps")
        #expect(viewModel.selection == nil,
            "An armed placement must not select the cell")
    }

    // MARK: - #939 sticky armed: non-matching non-empty cell is a no-op

    @Test func tapCell_armedOnDifferentDigitCell_noOpStaysArmed() async throws {
        let (viewModel, _) = try makeLiveViewModel()
        await viewModel.startOrResume()
        // Fill the one editable cell first, so it is "non-empty" (user-filled)
        // for the next tap.
        await viewModel.placeDigit(Self.emptyDigit, at: GridCoordinate(row: Self.emptyRow, column: Self.emptyCol))
        #expect(viewModel.board.digit(atRow: Self.emptyRow, column: Self.emptyCol) != nil)

        await viewModel.keypadDigit(9)  // arm a different digit
        #expect(viewModel.armedDigit == 9)

        await viewModel.tapCell(row: Self.emptyRow, column: Self.emptyCol)

        #expect(viewModel.board.digit(atRow: Self.emptyRow, column: Self.emptyCol) == Self.emptyDigit,
            "A mismatched tap must not alter the cell's existing digit")
        #expect(viewModel.selection == nil,
            "#939: a mismatched tap never falls back to cell-first selection")
        #expect(viewModel.armedDigit == 9,
            "#939: sticky armed — a mismatched tap (different digit) must stay armed")
    }

    @Test func tapCell_armedOnGivenCell_noOpStaysArmed() async throws {
        let (viewModel, _) = try makeLiveViewModel()
        await viewModel.startOrResume()
        await viewModel.keypadDigit(9)
        #expect(viewModel.armedDigit == 9)

        await viewModel.tapCell(row: Self.givenRow, column: Self.givenCol)

        #expect(viewModel.selection == nil,
            "Given cells stay non-selectable (Epic 9 / #473) even while armed")
        #expect(viewModel.armedDigit == 9,
            "#939: sticky armed — tapping a given cell while armed must still stay armed")
    }

    @Test func tapCell_armedOnMismatchCell_firesLightHaptic() async throws {
        let (viewModel, sound) = try makeLiveViewModelWithSound()
        await viewModel.keypadDigit(9)

        await viewModel.tapCell(row: Self.givenRow, column: Self.givenCol)

        #expect(sound.playedEvents == [.sudokuArmedMismatch],
            "#939: a sticky-armed mismatch tap must fire the light haptic-only cue")
    }

    // MARK: - #939 sticky armed: user-filled cell holding the armed digit clears

    // Both tests below use `makeLiveViewModelThreeEmptyCells()` (not the
    // single-empty-cell `makeLiveViewModel()`): filling the ONLY empty cell in
    // that fixture completes the whole puzzle, and GameSession's sticky
    // completion then makes `clearDigit`/`toggleNote` no-ops (same reasoning
    // as `undo_afterArmedPlacement_restoresEmptyCell`'s two-empty fixture
    // below) — which would make these tests about completion, not clearing.

    @Test func tapCell_armedOnSameDigitFilledCell_clearsAndStaysArmed() async throws {
        let (viewModel, _) = try makeLiveViewModelThreeEmptyCells()
        await viewModel.startOrResume()
        await viewModel.keypadDigit(Self.emptyDigit)
        await viewModel.tapCell(row: Self.emptyRow, column: Self.emptyCol)
        #expect(viewModel.board.digit(atRow: Self.emptyRow, column: Self.emptyCol) == Self.emptyDigit)
        #expect(viewModel.armedDigit == Self.emptyDigit)

        // Re-tap the SAME cell, still armed with the SAME digit it now holds.
        await viewModel.tapCell(row: Self.emptyRow, column: Self.emptyCol)

        #expect(viewModel.board.digit(atRow: Self.emptyRow, column: Self.emptyCol) == nil,
            "#939: tapping a user-filled cell holding the armed digit must clear it")
        #expect(viewModel.armedDigit == Self.emptyDigit,
            "#939: clearing via a sticky-armed tap must not disarm")
    }

    @Test func tapCell_armedOnSameDigitFilledCell_pencilMode_togglesNoteInsteadOfClearing() async throws {
        let (viewModel, _) = try makeLiveViewModelThreeEmptyCells()
        await viewModel.startOrResume()
        await viewModel.keypadDigit(Self.emptyDigit)
        await viewModel.tapCell(row: Self.emptyRow, column: Self.emptyCol)
        #expect(viewModel.board.digit(atRow: Self.emptyRow, column: Self.emptyCol) == Self.emptyDigit)
        viewModel.togglePencil()

        await viewModel.tapCell(row: Self.emptyRow, column: Self.emptyCol)

        #expect(viewModel.board.digit(atRow: Self.emptyRow, column: Self.emptyCol) == Self.emptyDigit,
            "#939: pencil mode keeps existing note-toggle semantics — it must not clear the digit")
        let index = Board.index(row: Self.emptyRow, column: Self.emptyCol)
        #expect(viewModel.notes.masks[index] & (1 << Self.emptyDigit) != 0,
            "#939: pencil mode toggles the note even on a cell already holding the armed digit")
        #expect(viewModel.armedDigit == Self.emptyDigit)
    }

    // MARK: - #939 sticky armed: survives a multi-cell sweep

    /// Three missing cells so a single armed digit can be placed into all
    /// three consecutively without the sweep running out of empty cells (and,
    /// per the two tests just above, without tripping the puzzle's sticky
    /// completion after the first placement).
    private func makeLiveViewModelThreeEmptyCells() throws -> (GameViewModel, GameSession) {
        var solution = Board()
        var cluesString = ""
        for index in 0..<Board.cellCount {
            let row = index / 9
            let col = index % 9
            let digit = (index % 9) + 1
            try solution.setDigit(digit, atIndex: index)
            cluesString.append((row == 0 && (col == 0 || col == 2 || col == 4)) ? "." : String(digit))
        }
        let clues = try Board(clues: cluesString)
        let puzzle = Puzzle(clues: clues, solution: solution, difficulty: .easy, generatorVersion: .v1, seed: 0)
        let session = GameSession(puzzle: puzzle)
        let viewModel = GameViewModel(
            identity: Self.identity,
            session: session,
            initialBoard: puzzle.clues,
            initialStatus: .idle,
            persistence: FakePersistence(),
            saveDebounceNanos: 0
        )
        return (viewModel, session)
    }

    @Test func tapCell_armedSurvivesConsecutivePlacements() async throws {
        let (viewModel, _) = try makeLiveViewModelThreeEmptyCells()
        await viewModel.startOrResume()
        await viewModel.keypadDigit(9)
        #expect(viewModel.armedDigit == 9)

        await viewModel.tapCell(row: 0, column: 0)
        await viewModel.tapCell(row: 0, column: 2)
        await viewModel.tapCell(row: 0, column: 4)

        #expect(viewModel.board.digit(atRow: 0, column: 0) == 9)
        #expect(viewModel.board.digit(atRow: 0, column: 2) == 9)
        #expect(viewModel.board.digit(atRow: 0, column: 4) == 9)
        #expect(viewModel.armedDigit == 9,
            "#939: the digit must stay armed across ≥3 consecutive placements")
        #expect(viewModel.selection == nil)
    }

    // MARK: - select-then-keypad unchanged (today's cell-first flow)

    @Test func keypadDigit_withSelection_placesIntoSelectionUnchanged() async throws {
        let (viewModel, _) = try makeLiveViewModel()
        await viewModel.startOrResume()
        viewModel.select(row: Self.emptyRow, column: Self.emptyCol)
        #expect(viewModel.selection != nil)

        await viewModel.keypadDigit(Self.emptyDigit)

        #expect(viewModel.board.digit(atRow: Self.emptyRow, column: Self.emptyCol) == Self.emptyDigit,
            "With a live selection, keypadDigit must place directly (today's flow)")
        #expect(viewModel.armedDigit == nil,
            "A selection-driven placement must never arm a digit")
    }

    // MARK: - arming clears selection and vice versa (invariant)

    @Test func armingDigit_clearsExistingSelection() async throws {
        let (viewModel, _) = try makeLiveViewModel()
        viewModel.select(row: Self.emptyRow, column: Self.emptyCol)
        #expect(viewModel.selection != nil)

        // Directly exercise the invariant-enforcing mutator (armDigit only
        // fires from keypadDigit when selection == nil in the real UI flow,
        // but the invariant itself must hold unconditionally).
        viewModel.armDigit(5)

        #expect(viewModel.selection == nil, "Arming must clear any existing selection")
        #expect(viewModel.armedDigit == 5)
    }

    @Test func selecting_clearsExistingArmedDigit() async throws {
        let (viewModel, _) = try makeLiveViewModel()
        await viewModel.keypadDigit(5)
        #expect(viewModel.armedDigit == 5)

        viewModel.select(row: Self.emptyRow, column: Self.emptyCol)

        #expect(viewModel.armedDigit == nil, "Selecting a cell must clear any armed digit")
    }

    @Test func moveSelection_clearsExistingArmedDigit() async throws {
        let (viewModel, _) = try makeLiveViewModel()
        await viewModel.keypadDigit(5)
        #expect(viewModel.armedDigit == 5)

        viewModel.moveSelection(rowDelta: 0, columnDelta: 1)

        #expect(viewModel.armedDigit == nil, "Keyboard-driven selection must also disarm")
    }

    // MARK: - pencil + armed toggles notes

    @Test func tapCell_armedInPencilMode_togglesNoteInsteadOfPlacing() async throws {
        let (viewModel, _) = try makeLiveViewModel()
        await viewModel.startOrResume()
        viewModel.togglePencil()
        #expect(viewModel.pencilMode == true)
        await viewModel.keypadDigit(Self.emptyDigit)
        #expect(viewModel.armedDigit == Self.emptyDigit)

        await viewModel.tapCell(row: Self.emptyRow, column: Self.emptyCol)

        #expect(viewModel.board.digit(atRow: Self.emptyRow, column: Self.emptyCol) == nil,
            "Pencil mode must toggle a note, not place a digit")
        let index = Board.index(row: Self.emptyRow, column: Self.emptyCol)
        #expect(viewModel.notes.masks[index] & (1 << Self.emptyDigit) != 0,
            "The armed digit's note must be toggled on")
        #expect(viewModel.armedDigit == Self.emptyDigit,
            "The digit must stay armed after a note toggle")
    }

    // MARK: - undo after armed placement restores correctly

    /// Two missing cells (unlike `makeLiveViewModel`'s single missing cell)
    /// so placing into ONE of them doesn't trip GameSession's sticky
    /// completion — completion blocks `undo()` by documented design, which
    /// would otherwise make this test about completion, not undo.
    private func makeLiveViewModelTwoEmptyCells() throws -> (GameViewModel, GameSession) {
        var solution = Board()
        var cluesString = ""
        for index in 0..<Board.cellCount {
            let row = index / 9
            let col = index % 9
            let digit = (index % 9) + 1
            try solution.setDigit(digit, atIndex: index)
            cluesString.append((row == 0 && (col == 0 || col == 2)) ? "." : String(digit))
        }
        let clues = try Board(clues: cluesString)
        let puzzle = Puzzle(clues: clues, solution: solution, difficulty: .easy, generatorVersion: .v1, seed: 0)
        let session = GameSession(puzzle: puzzle)
        let viewModel = GameViewModel(
            identity: Self.identity,
            session: session,
            initialBoard: puzzle.clues,
            initialStatus: .idle,
            persistence: FakePersistence(),
            saveDebounceNanos: 0
        )
        return (viewModel, session)
    }

    @Test func undo_afterArmedPlacement_restoresEmptyCell() async throws {
        let (viewModel, _) = try makeLiveViewModelTwoEmptyCells()
        await viewModel.startOrResume()
        await viewModel.keypadDigit(Self.emptyDigit)
        await viewModel.tapCell(row: Self.emptyRow, column: Self.emptyCol)
        #expect(viewModel.board.digit(atRow: Self.emptyRow, column: Self.emptyCol) == Self.emptyDigit)
        #expect(viewModel.canUndo == true)

        await viewModel.undo()

        #expect(viewModel.board.digit(atRow: Self.emptyRow, column: Self.emptyCol) == nil,
            "Undo after an armed placement must restore the cell exactly like a cell-first placement")
        #expect(viewModel.armedDigit == Self.emptyDigit,
            "Undo must not alter armedDigit")
    }
}
