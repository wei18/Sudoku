// GameSessionPlacementOutcomeTests (#1119) — `placeDigit` returns the
// before/after pair it produced itself, and decides completion before its
// first suspension so interleaved calls cannot share it.

import Foundation
import SudokuEngine
import Testing
import SudokuGameState

/// Telemetry whose `dispatch(.digitPlaced)` really suspends until `release()`;
/// `waitForDigitPlacedArrivals` returns once that many calls are suspended.
private actor GatedTelemetry: GameStateTelemetry {
    private(set) var events: [GameStateEvent] = []
    private var isReleased = false
    private var gateWaiters: [CheckedContinuation<Void, Never>] = []
    private var arrivals = 0
    private var arrivalWaiter: (count: Int, continuation: CheckedContinuation<Void, Never>)?

    func dispatch(_ event: GameStateEvent) async {
        events.append(event)
        guard case .digitPlaced = event else { return }
        arrivals += 1
        if let waiter = arrivalWaiter, arrivals >= waiter.count {
            arrivalWaiter = nil
            waiter.continuation.resume()
        }
        if isReleased { return }
        await withCheckedContinuation { gateWaiters.append($0) }
    }

    func waitForDigitPlacedArrivals(_ count: Int) async {
        if arrivals >= count { return }
        await withCheckedContinuation { arrivalWaiter = (count, $0) }
    }

    func release() {
        isReleased = true
        for waiter in gateWaiters { waiter.resume() }
        gateWaiters = []
    }
}

/// Recording telemetry that never suspends.
private actor RecordingTelemetry: GameStateTelemetry {
    private(set) var events: [GameStateEvent] = []
    func dispatch(_ event: GameStateEvent) async { events.append(event) }
}

/// Solution digit at (row, column) is `column + 1` (shifted Latin square, as
/// `TestPuzzles.nearSolved`); every coordinate in `missing` is blank.
private func puzzle(missing: [(row: Int, col: Int)]) -> Puzzle {
    var solution = Board()
    var clues = ""
    for index in 0..<Board.cellCount {
        let digit = (index % 9) + 1
        // swiftlint:disable:next force_try
        try! solution.setDigit(digit, atIndex: index)
        let isMissing = missing.contains { $0.row == index / 9 && $0.col == index % 9 }
        clues.append(isMissing ? "." : String(digit))
    }
    // swiftlint:disable:next force_try
    let clueBoard = try! Board(clues: clues)
    return Puzzle(
        clues: clueBoard, solution: solution,
        difficulty: .easy, generatorVersion: .v1, seed: 0
    )
}

@Suite("GameSession placeDigit outcome (#1119)")
struct GameSessionPlacementOutcomeTests {

    @Test("outcome pair: before lacks the digit, after has exactly it, ordinary placement is not a completion")
    func ordinaryOutcomePair() async throws {
        let session = GameSession(puzzle: puzzle(missing: [(0, 0), (0, 1)]))
        try await session.start()
        let outcome = try await session.placeDigit(row: 0, col: 0, digit: 1)

        #expect(outcome.boardBefore.digit(atRow: 0, column: 0) == nil)
        #expect(outcome.boardAfter.digit(atRow: 0, column: 0) == 1)
        #expect(outcome.completedGame == false)
        var expected = outcome.boardBefore
        try expected.setDigit(1, atRow: 0, column: 0)
        #expect(outcome.boardAfter == expected, "after differs from before only by the placed digit")
    }

    @Test("outcome pair: the completing placement reports completedGame")
    func completingOutcome() async throws {
        let session = GameSession(puzzle: puzzle(missing: [(0, 0)]))
        try await session.start()
        let outcome = try await session.placeDigit(row: 0, col: 0, digit: 1)

        #expect(outcome.completedGame == true)
        #expect(outcome.boardBefore.digit(atRow: 0, column: 0) == nil)
        #expect(outcome.boardAfter.digit(atRow: 0, column: 0) == 1)
        #expect(await session.status == .completed)
    }

    @Test("telemetry order: digitPlaced precedes sessionCompleted, payloads unchanged")
    func completionTelemetryOrder() async throws {
        let spy = RecordingTelemetry()
        let session = GameSession(puzzle: puzzle(missing: [(0, 0)]), telemetry: spy)
        try await session.start()
        try await session.placeDigit(row: 0, col: 0, digit: 1)

        let events = await spy.events
        // (0,0)=1 repeats the 1 already in column 0 of this fixture, so one mistake.
        #expect(Array(events.suffix(2)) == [
            .digitPlaced(row: 0, col: 0, digit: 1, previous: nil),
            .sessionCompleted(elapsedSeconds: 0, mistakeCount: 1),
        ])
    }

    @Test("re-entrancy: two placements suspended in telemetry complete the game exactly once")
    func interleavedLastTwoCells() async throws {
        let gated = GatedTelemetry()
        let session = GameSession(puzzle: puzzle(missing: [(0, 0), (0, 1)]), telemetry: gated)
        try await session.start()

        let first = Task { try await session.placeDigit(row: 0, col: 0, digit: 1) }
        let second = Task { try await session.placeDigit(row: 0, col: 1, digit: 2) }
        await gated.waitForDigitPlacedArrivals(2)
        await gated.release()
        let outcomeOne = try await first.value
        let outcomeTwo = try await second.value

        let outcomes = [outcomeOne, outcomeTwo]
        #expect(outcomes.filter(\.completedGame).count == 1)
        let completed = await gated.events.filter {
            if case .sessionCompleted = $0 { return true }
            return false
        }
        #expect(completed.count == 1)
        // Whichever call ran first never sees the other's digit.
        let firstToWrite = outcomes.first { $0.boardBefore.digit(atRow: 0, column: 0) == nil
            && $0.boardBefore.digit(atRow: 0, column: 1) == nil }
        let leaked = try #require(firstToWrite)
        #expect(leaked.completedGame == false)
        #expect(leaked.boardAfter.cells.filter { $0 != 0 }.count
            == leaked.boardBefore.cells.filter { $0 != 0 }.count + 1)
        #expect(await session.status == .completed)
    }
}
