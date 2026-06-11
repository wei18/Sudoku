// GameViewModelFixedCellTests — Epic 9 (SDD-003): fixed cells (isFixed == true)
// must not be selectable, not produce a selection highlight, and not accept
// any edits when tapped.
//
// Spec: docs/superpowers/specs/2026-06-12-sdd-003-puzzle-platform-ux-refresh.md §Epic 9

import Foundation
import GameState
import Persistence
import PersistenceTesting
import PuzzleStore
import SudokuEngine
import SudokuKitTesting
import Testing
@testable import SudokuUI

@MainActor
@Suite("GameViewModel — fixed-cell interaction (Epic 9 / SDD-003)")
struct GameViewModelFixedCellTests {

    // latinSquarePuzzle() has every cell as a given EXCEPT (0,0), which is empty.
    // Row 0, col 1 holds digit 2 and is a given — perfect target for fixed-cell tests.
    private static let givenRow = 0
    private static let givenCol = 1  // isFixed == true
    private static let editableRow = 0
    private static let editableCol = 0  // isFixed == false (the one missing cell)

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

    // MARK: - select() must ignore fixed cells

    @Test func tappingFixedCell_doesNotSetSelection() throws {
        let (viewModel, _) = try makeLiveViewModel()
        #expect(viewModel.selection == nil)

        viewModel.select(row: Self.givenRow, column: Self.givenCol)

        #expect(viewModel.selection == nil,
            "Tapping a given (fixed) cell must not update selection")
    }

    @Test func tappingEditableCell_doesSetSelection() throws {
        let (viewModel, _) = try makeLiveViewModel()

        viewModel.select(row: Self.editableRow, column: Self.editableCol)

        #expect(viewModel.selection == GridCoordinate(row: Self.editableRow, column: Self.editableCol),
            "Tapping an editable cell must update selection")
    }

    @Test func selectingFixedCell_doesNotOverwriteExistingSelection() throws {
        let (viewModel, _) = try makeLiveViewModel()
        // First select an editable cell.
        viewModel.select(row: Self.editableRow, column: Self.editableCol)
        let priorSelection = viewModel.selection

        // Now tap a given cell — selection must not change.
        viewModel.select(row: Self.givenRow, column: Self.givenCol)

        #expect(viewModel.selection == priorSelection,
            "Tapping a fixed cell must leave the prior selection unchanged")
    }

    // MARK: - placeDigit must still be a no-op for fixed cells (regression guard)

    // This behavior predates Epic 9 (placeDigit had its own givenMask gate);
    // the test ensures the new select() guard didn't disturb the mutation path.
    @Test func placeDigit_onFixedCell_isNoOp() async throws {
        let (viewModel, _) = try makeLiveViewModel()
        await viewModel.startOrResume()
        // Confirm (0,1) is a given with digit 2.
        #expect(viewModel.board.givenMask[Board.index(row: Self.givenRow, column: Self.givenCol)] == true)
        let originalDigit = viewModel.board.digit(atRow: Self.givenRow, column: Self.givenCol)

        await viewModel.placeDigit(9, at: GridCoordinate(row: Self.givenRow, column: Self.givenCol))

        #expect(viewModel.board.digit(atRow: Self.givenRow, column: Self.givenCol) == originalDigit,
            "placeDigit on a fixed cell must be a no-op")
    }
}
