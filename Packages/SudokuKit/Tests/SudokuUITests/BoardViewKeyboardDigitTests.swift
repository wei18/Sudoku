// BoardViewKeyboardDigitTests — #790 fix 1: the Mac hardware-keyboard digit
// path must share the SAME arm/place/pencil-note dispatch as the pointer-
// driven digit pad, not the legacy `placeDigit(_:)` (which silently no-ops
// with no selection — no way to arm a digit from the keyboard at all).
//
// `BoardView.handleKeyPress` itself is NOT unit-testable: SwiftUI's `KeyPress`
// has no public initializer (confirmed against Apple's Accessibility/SwiftUI
// sample code, which only ever receives one from `onKeyPress`'s closure).
// `dispatchKeyboardDigit(_:)` is the extracted, directly-callable entry point
// `handleKeyPress`'s digit branch forwards to — this is the closest testable
// proxy for "what a digit key does."

import Foundation
import SudokuGameState
import Persistence
import PersistenceTesting
import SudokuPersistence
import SudokuEngine
import SudokuKitTesting
import Testing
@testable import SudokuUI

@MainActor
@Suite("BoardView — keyboard digit dispatch (#790 fix 1)")
struct BoardViewKeyboardDigitTests {

    // Same fixture shape as GameViewModelDigitFirstTests: every cell is a
    // given EXCEPT (0,0), whose solution digit is 1.
    private static let emptyRow = 0
    private static let emptyCol = 0
    private static let emptyDigit = 1

    private static let identity = PuzzleIdentity.practice(salt: 9, difficulty: .easy)

    private func makeBoardView() throws -> (BoardView, GameViewModel) {
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
        return (BoardView(viewModel: viewModel), viewModel)
    }

    @Test func noSelection_armsDigitInsteadOfNoOp() async throws {
        let (boardView, viewModel) = try makeBoardView()
        #expect(viewModel.selection == nil)
        #expect(viewModel.armedDigit == nil)

        await boardView.dispatchKeyboardDigit(5)

        #expect(viewModel.armedDigit == 5,
            "A digit key with no selection must arm the digit (old code called placeDigit, a silent no-op)")
    }

    @Test func withSelection_placesDirectly() async throws {
        let (boardView, viewModel) = try makeBoardView()
        await viewModel.startOrResume()
        viewModel.select(row: Self.emptyRow, column: Self.emptyCol)

        await boardView.dispatchKeyboardDigit(Self.emptyDigit)

        #expect(viewModel.board.digit(atRow: Self.emptyRow, column: Self.emptyCol) == Self.emptyDigit,
            "With a live selection, a digit key must place directly (today's cell-first flow, unchanged)")
        #expect(viewModel.armedDigit == nil)
    }

    @Test func pencilModeWithSelection_togglesNoteNotDigit() async throws {
        let (boardView, viewModel) = try makeBoardView()
        await viewModel.startOrResume()
        viewModel.togglePencil()
        viewModel.select(row: Self.emptyRow, column: Self.emptyCol)

        await boardView.dispatchKeyboardDigit(Self.emptyDigit)

        #expect(viewModel.board.digit(atRow: Self.emptyRow, column: Self.emptyCol) == nil,
            "Pencil mode must toggle a note, not place a digit — preserved from the old placeOrToggle behavior")
        let index = Board.index(row: Self.emptyRow, column: Self.emptyCol)
        #expect(viewModel.notes.masks[index] & (1 << Self.emptyDigit) != 0)
    }
}
