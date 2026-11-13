// GameViewModelCellFeedbackTests (#1018) — the Sudoku view-model half of the
// per-cell success animation: a placement that newly completes a row / column
// / box begins ONE unit-sweep event in `CellFeedbackState`, the event expires
// on its own, and feedback never blocks or drops input (the VM only WRITES to
// the feedback state). Expiry is released by hand through an injected sleeper
// and settled by awaiting the expiry Task's value, never by `Task.yield()`.

import Foundation
import GameShellUI
import SudokuGameState
import Persistence
import PersistenceTesting
import SudokuPersistence
import SudokuEngine
import Testing
@testable import SudokuUI

/// A hand-released sleeper gate. A watchdog releases it after 30 s (wall-clock; a
/// full-suite run can starve the main actor for seconds, which a 5 s bound did
/// not survive in the Minesweeper twin of this test) so a
/// regression (e.g. placement awaiting expiry) fails an assertion instead of
/// hanging the run.
private actor Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var isReleased = false

    func wait() async {
        if isReleased { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        isReleased = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}

private func makeGate() -> Gate {
    let gate = Gate()
    Task {
        try? await Task.sleep(for: .seconds(30))
        await gate.release()
    }
    return gate
}

private enum Path: Sendable, CaseIterable {
    case live
    case preview
}

@MainActor
@Suite("GameViewModel — #1018 unit-sweep cell feedback")
struct GameViewModelCellFeedbackTests {

    private static let identity = PuzzleIdentity.practice(salt: 7, difficulty: .easy)

    /// Same canonical solved board as `GameViewModelAudioTests`.
    private static let solvedDigits = Array(
        "534678912672195348198342567859761423426853791713924856961537284287419635345286179"
    ).map { Int(String($0)) ?? 0 }

    private func solution(_ row: Int, _ column: Int) -> Int {
        Self.solvedDigits[Board.index(row: row, column: column)]
    }

    private func makePuzzle(blanks: Set<GridCoordinate>) throws -> Puzzle {
        var solved = Board()
        var cluesString = ""
        for index in 0..<Board.cellCount {
            let digit = Self.solvedDigits[index]
            try solved.setDigit(digit, atIndex: index)
            let coord = GridCoordinate(row: index / 9, column: index % 9)
            cluesString.append(blanks.contains(coord) ? "." : String(digit))
        }
        let clues = try Board(clues: cluesString)
        return Puzzle(clues: clues, solution: solved, difficulty: .easy, generatorVersion: .v1, seed: 0)
    }

    private func makeViewModel(
        _ path: Path,
        blanks: Set<GridCoordinate>,
        sleeper: @escaping CellFeedbackSleeper
    ) async throws -> GameViewModel {
        let puzzle = try makePuzzle(blanks: blanks)
        switch path {
        case .live:
            let viewModel = GameViewModel(
                identity: Self.identity,
                session: GameSession(puzzle: puzzle),
                initialBoard: puzzle.clues,
                initialStatus: .idle,
                persistence: FakePersistence(),
                saveDebounceNanos: 0,
                cellFeedbackSleeper: sleeper
            )
            await viewModel.startOrResume()
            return viewModel
        case .preview:
            return GameViewModel(
                identity: Self.identity,
                board: puzzle.clues,
                cellFeedbackSleeper: sleeper
            )
        }
    }

    private func settle(_ viewModel: GameViewModel) async {
        await viewModel.cellFeedback.waitForPendingExpiries()
    }

    private func coord(_ row: Int, _ column: Int) -> GridCoordinate {
        GridCoordinate(row: row, column: column)
    }

    // MARK: 1. idle -> animating -> idle

    @Test("completing a row begins one event for exactly that row, then expires", arguments: Path.allCases)
    fileprivate func rowCompletionLifecycle(path: Path) async throws {
        // (0,0) + (1,0) blank: filling (0,0) completes row 0 only — column 0
        // and box 0 still hold the blank (1,0).
        let gate = makeGate()
        let viewModel = try await makeViewModel(
            path, blanks: [coord(0, 0), coord(1, 0)], sleeper: { _ in await gate.wait() }
        )
        #expect(viewModel.cellFeedback.isIdle)

        await viewModel.placeDigit(solution(0, 0), at: coord(0, 0))

        let events = viewModel.cellFeedback.activeEvents.map(\.event)
        #expect(events.count == 1)
        #expect(events.first?.coordinate == coord(0, 0))
        #expect(events.first?.units == [.row(0)])
        #expect(!viewModel.cellFeedback.isIdle)

        await gate.release()
        await settle(viewModel)
        #expect(viewModel.cellFeedback.isIdle)
    }

    // MARK: 2. several units at once, stable order

    @Test("a placement completing a row and a box yields one event, row before box", arguments: Path.allCases)
    fileprivate func rowAndBoxInStableOrder(path: Path) async throws {
        // (0,0) + (3,0) blank: filling (0,0) completes row 0 and box 0, not column 0.
        let gate = makeGate()
        let viewModel = try await makeViewModel(
            path, blanks: [coord(0, 0), coord(3, 0)], sleeper: { _ in await gate.wait() }
        )

        await viewModel.placeDigit(solution(0, 0), at: coord(0, 0))

        let events = viewModel.cellFeedback.activeEvents.map(\.event)
        #expect(events.count == 1)
        #expect(events.first?.units == [.row(0), .box(0)])
        await gate.release()
        await settle(viewModel)
    }

    @Test("completing row, column and box at once lists row, column, box", arguments: Path.allCases)
    fileprivate func allThreeUnitsInStableOrder(path: Path) async throws {
        let gate = makeGate()
        let viewModel = try await makeViewModel(
            path, blanks: [coord(0, 0), coord(4, 4)], sleeper: { _ in await gate.wait() }
        )

        await viewModel.placeDigit(solution(0, 0), at: coord(0, 0))

        #expect(viewModel.cellFeedback.activeEvents.map(\.event.units) == [[.row(0), .column(0), .box(0)]])
        await gate.release()
        await settle(viewModel)
    }

    // MARK: 3. no event

    @Test("no event for a non-completing placement, a clear, or a conflicting fill", arguments: Path.allCases)
    fileprivate func noEventCases(path: Path) async throws {
        let gate = makeGate()
        let blanks: Set<GridCoordinate> = [coord(0, 0), coord(0, 1), coord(1, 0), coord(1, 1), coord(8, 8)]
        let viewModel = try await makeViewModel(path, blanks: blanks, sleeper: { _ in await gate.wait() })

        // Non-completing: (0,1) shares row 0 / box 0 with other blanks, column 1 with (1,1).
        await viewModel.placeDigit(solution(0, 1), at: coord(0, 1))
        #expect(viewModel.cellFeedback.pendingExpiries.isEmpty)

        // Clear of that cell.
        await viewModel.placeDigit(nil, at: coord(0, 1))
        #expect(viewModel.cellFeedback.pendingExpiries.isEmpty)

        // Conflicting fill of the last blank in row 8 / column 8 / box 8:
        // (8,8) solution is 9; place 1, which repeats in row 8 -> conflict.
        await viewModel.placeDigit(1, at: coord(8, 8))
        #expect(viewModel.errorIndices.contains(Board.index(row: 8, column: 8)))
        #expect(viewModel.cellFeedback.pendingExpiries.isEmpty)
        #expect(viewModel.cellFeedback.isIdle)
        await gate.release()
    }

    @Test("a clear after a completion begins no second event", arguments: Path.allCases)
    fileprivate func clearAfterCompletionBeginsNothing(path: Path) async throws {
        let gate = makeGate()
        let viewModel = try await makeViewModel(
            path, blanks: [coord(0, 0), coord(4, 4)], sleeper: { _ in await gate.wait() }
        )
        await viewModel.placeDigit(solution(0, 0), at: coord(0, 0))
        #expect(viewModel.cellFeedback.pendingExpiries.count == 1)

        await viewModel.placeDigit(nil, at: coord(0, 0))
        #expect(viewModel.cellFeedback.pendingExpiries.count == 1)
        await gate.release()
        await settle(viewModel)
    }

    // MARK: 4. THE INPUT TEST

    @Test("feedback never blocks or drops input: overlapping animations, three placements land")
    func inputNeverWaitsOnFeedback() async throws {
        let gate = makeGate()
        // Unit A around (0,0), unit B around (8,8), and a 2x2 blank cluster in
        // box 4 so (3,3) completes nothing.
        let blanks: Set<GridCoordinate> = [
            coord(0, 0), coord(8, 8), coord(3, 3), coord(3, 4), coord(4, 3), coord(4, 4)
        ]
        let viewModel = try await makeViewModel(.live, blanks: blanks, sleeper: { _ in await gate.wait() })

        await viewModel.placeDigit(solution(0, 0), at: coord(0, 0))
        #expect(viewModel.cellFeedback.activeEvents.count == 1)
        #expect(await gate.isReleased == false)

        // Second completion while A's sleeper is still held. If placement
        // awaited expiry it would only return after the 30 s watchdog, by
        // which time A would already have ended and the asserts below fail.
        await viewModel.placeDigit(solution(8, 8), at: coord(8, 8))
        #expect(await gate.isReleased == false)
        #expect(viewModel.board.digit(atRow: 8, column: 8) == solution(8, 8))
        let events = viewModel.cellFeedback.activeEvents.map(\.event)
        #expect(events.map(\.coordinate) == [coord(0, 0), coord(8, 8)])
        #expect(events.map(\.units) == [[.row(0), .column(0), .box(0)], [.row(8), .column(8), .box(8)]])

        // An ordinary placement during both animations also lands, no event.
        await viewModel.placeDigit(solution(3, 3), at: coord(3, 3))
        #expect(await gate.isReleased == false)
        #expect(viewModel.board.digit(atRow: 3, column: 3) == solution(3, 3))
        #expect(viewModel.cellFeedback.activeEvents.count == 2)

        await gate.release()
        await settle(viewModel)
        #expect(viewModel.cellFeedback.isIdle)
        #expect(viewModel.cellFeedback.pendingExpiries.isEmpty, "pending expiries not empty after a full sequence")
    }

    // MARK: 6. digit-first entry point

    @Test("tapCell with an armed digit that completes a unit begins an event", arguments: Path.allCases)
    fileprivate func digitFirstCompletionBeginsEvent(path: Path) async throws {
        let gate = makeGate()
        let viewModel = try await makeViewModel(
            path, blanks: [coord(0, 0), coord(1, 0)], sleeper: { _ in await gate.wait() }
        )
        viewModel.armDigit(solution(0, 0))

        await viewModel.tapCell(row: 0, column: 0)

        #expect(viewModel.cellFeedback.activeEvents.map(\.event.units) == [[.row(0)]])
        await gate.release()
        await settle(viewModel)
        #expect(viewModel.cellFeedback.isIdle)
    }

    // MARK: Unit identity

    @Test("unit cell indices are in sweep order")
    func unitCellIndices() {
        #expect(SudokuUnit.row(2).cellIndices == (0..<9).map { Board.index(row: 2, column: $0) })
        #expect(SudokuUnit.column(5).cellIndices == (0..<9).map { Board.index(row: $0, column: 5) })
        #expect(SudokuUnit.box(4).cellIndices == [
            Board.index(row: 3, column: 3), Board.index(row: 3, column: 4), Board.index(row: 3, column: 5),
            Board.index(row: 4, column: 3), Board.index(row: 4, column: 4), Board.index(row: 4, column: 5),
            Board.index(row: 5, column: 3), Board.index(row: 5, column: 4), Board.index(row: 5, column: 5),
        ])
    }
}
