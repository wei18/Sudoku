// GameViewModelPlacementRaceTests (#1119) — two placements whose tasks
// interleave across the session call must each be credited only with what
// they produced: one section-cleared sound, one unit sweep, one win.
//
// Every test drives the view model the way `BoardView` does: one unstructured
// `Task` per input event (`keypadDigit` from the digit pad, `tapCell` from a
// board cell), all created before any of them has run. Each task therefore
// runs up to its session call and suspends there before the next one starts,
// which is the interleaving the issue describes.

import Foundation
import GameAudio
import GameAudioTesting
import GameShellUI
import SudokuGameState
import Persistence
import PersistenceTesting
import SudokuPersistence
import SudokuEngine
import Testing
@testable import SudokuUI

/// Never released by the tests until the end, so sweep events stay active and
/// can be counted. A watchdog releases it after 30 s so a regression fails an
/// assertion instead of hanging the run.
private actor PlacementRaceGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false

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

private func makePlacementRaceGate() -> PlacementRaceGate {
    let gate = PlacementRaceGate()
    Task {
        try? await Task.sleep(for: .seconds(30))
        await gate.release()
    }
    return gate
}

@MainActor
@Suite("GameViewModel — #1119 interleaved placements")
struct GameViewModelPlacementRaceTests {

    private static let identity = PuzzleIdentity.practice(salt: 7, difficulty: .easy)

    /// Same canonical solved board as `GameViewModelAudioTests`.
    private static let solvedDigits = Array(
        "534678912672195348198342567859761423426853791713924856961537284287419635345286179"
    ).map { Int(String($0)) ?? 0 }

    private func solution(_ row: Int, _ column: Int) -> Int {
        Self.solvedDigits[Board.index(row: row, column: column)]
    }

    private func coord(_ row: Int, _ column: Int) -> GridCoordinate {
        GridCoordinate(row: row, column: column)
    }

    private func makeViewModel(
        blanks: Set<GridCoordinate>,
        gate: PlacementRaceGate
    ) async throws -> (GameViewModel, FakeSoundPlaying) {
        var solved = Board()
        var cluesString = ""
        for index in 0..<Board.cellCount {
            let digit = Self.solvedDigits[index]
            try solved.setDigit(digit, atIndex: index)
            let cell = GridCoordinate(row: index / 9, column: index % 9)
            cluesString.append(blanks.contains(cell) ? "." : String(digit))
        }
        let puzzle = Puzzle(
            clues: try Board(clues: cluesString), solution: solved,
            difficulty: .easy, generatorVersion: .v1, seed: 0
        )
        let sound = FakeSoundPlaying()
        let viewModel = GameViewModel(
            identity: Self.identity,
            session: GameSession(puzzle: puzzle),
            initialBoard: puzzle.clues,
            initialStatus: .idle,
            persistence: FakePersistence(),
            soundPlayer: sound,
            saveDebounceNanos: 0,
            cellFeedbackSleeper: { _ in await gate.wait() }
        )
        await viewModel.startOrResume()
        return (viewModel, sound)
    }

    /// Row 0 is missing (0,0) and (0,1); (1,0) and (1,1) are blank too so no
    /// column or box can complete. Only the placement that fills the second
    /// cell completes row 0.
    private static let rowBlanks: Set<GridCoordinate> = [
        GridCoordinate(row: 0, column: 0), GridCoordinate(row: 0, column: 1),
        GridCoordinate(row: 1, column: 0), GridCoordinate(row: 1, column: 1),
    ]

    private func sectionCleared(_ sound: FakeSoundPlaying) -> Int {
        sound.playedEvents.filter { $0 == .sudokuSectionCleared }.count
    }

    // MARK: Control — the same inputs, one at a time

    @Test("serial: filling the last two cells of a row plays one section-cleared sound and one sweep")
    func serialPlacementsCreditTheCompletingPlacementOnce() async throws {
        let gate = makePlacementRaceGate()
        let (viewModel, sound) = try await makeViewModel(blanks: Self.rowBlanks, gate: gate)

        viewModel.select(row: 0, column: 0)
        await viewModel.keypadDigit(solution(0, 0))
        await viewModel.tapCell(row: 0, column: 1)
        await viewModel.keypadDigit(solution(0, 1))

        #expect(sectionCleared(sound) == 1)
        let events = viewModel.cellFeedback.activeEvents.map(\.event)
        #expect(events.map(\.coordinate) == [coord(0, 1)])
        #expect(events.map(\.units) == [[.row(0)]])

        await gate.release()
        await viewModel.cellFeedback.waitForPendingExpiries()
    }

    // MARK: The race — digit, cell, digit as three UI tasks

    @Test("interleaved: one section-cleared sound and one sweep, credited to the completing placement")
    func interleavedPlacementsCreditTheCompletingPlacementOnce() async throws {
        let gate = makePlacementRaceGate()
        let (viewModel, sound) = try await makeViewModel(blanks: Self.rowBlanks, gate: gate)
        viewModel.select(row: 0, column: 0)

        let first = solution(0, 0)
        let second = solution(0, 1)
        let digitOne = Task { await viewModel.keypadDigit(first) }
        let cellTap = Task { await viewModel.tapCell(row: 0, column: 1) }
        let digitTwo = Task { await viewModel.keypadDigit(second) }
        await digitOne.value
        await cellTap.value
        await digitTwo.value

        #expect(viewModel.board.digit(atIndex: Board.index(row: 0, column: 0)) == first)
        #expect(viewModel.board.digit(atIndex: Board.index(row: 0, column: 1)) == second)
        #expect(sectionCleared(sound) == 1, "section-cleared played \(sectionCleared(sound)) times: \(sound.playedEvents)")
        let events = viewModel.cellFeedback.activeEvents.map(\.event)
        #expect(events.map(\.units) == [[.row(0)]], "sweeps: \(events)")
        #expect(events.map(\.coordinate) == [coord(0, 1)], "the sweep belongs to the placement that completed the row")

        await gate.release()
        await viewModel.cellFeedback.waitForPendingExpiries()
    }

    // MARK: The same baseline shape on the win transition

    @Test("interleaved: the last two cells of the board play one win sound")
    func interleavedFinalPlacementsWinOnce() async throws {
        let gate = makePlacementRaceGate()
        let (viewModel, sound) = try await makeViewModel(blanks: [coord(0, 0), coord(0, 1)], gate: gate)
        viewModel.select(row: 0, column: 0)

        let first = solution(0, 0)
        let second = solution(0, 1)
        let digitOne = Task { await viewModel.keypadDigit(first) }
        let cellTap = Task { await viewModel.tapCell(row: 0, column: 1) }
        let digitTwo = Task { await viewModel.keypadDigit(second) }
        await digitOne.value
        await cellTap.value
        await digitTwo.value

        #expect(viewModel.status == .completed)
        let wins = sound.playedEvents.filter { $0 == .sudokuWin }.count
        #expect(wins == 1, "win played \(wins) times: \(sound.playedEvents)")

        await gate.release()
        await viewModel.cellFeedback.waitForPendingExpiries()
    }

    // MARK: Digit-first — two cell taps with one armed digit

    /// The shortest UI route: a sticky-armed digit and two board-cell taps,
    /// nothing in between. (0,0) and (1,5) both take a 5 and share no unit.
    @Test("digit-first: two cell taps filling the last two cells play one win sound")
    func digitFirstFinalTapsWinOnce() async throws {
        let gate = makePlacementRaceGate()
        let (viewModel, sound) = try await makeViewModel(blanks: [coord(0, 0), coord(1, 5)], gate: gate)
        #expect(solution(0, 0) == solution(1, 5))
        viewModel.armDigit(solution(0, 0))

        let tapOne = Task { await viewModel.tapCell(row: 0, column: 0) }
        let tapTwo = Task { await viewModel.tapCell(row: 1, column: 5) }
        await tapOne.value
        await tapTwo.value

        #expect(viewModel.status == .completed)
        let wins = sound.playedEvents.filter { $0 == .sudokuWin }.count
        #expect(wins == 1, "win played \(wins) times: \(sound.playedEvents)")

        await gate.release()
        await viewModel.cellFeedback.waitForPendingExpiries()
    }
}
