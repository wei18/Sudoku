// GameStateTelemetryAdapter — production bridge from GameState's local
// `GameStateTelemetry` seam to the Telemetry fan-out facade.
//
// Why this lives in the Telemetry target (not SudokuKitTesting):
//   - The adapter is real production wiring used by the App's composition
//     root (docs/v1/design.md §How.1); test-only modules cannot ship it.
//   - GameState owns the upstream protocol + event surface; Telemetry owns
//     the downstream facade. The adapter is exactly the bridge between
//     the two, so Telemetry is the natural home.
//
// Why GameState stays on its local seam (no import Telemetry there):
//   - Phase 3 needed to compile without Phase 4. The seam decouples the
//     two ordering-wise.
//   - Keeping GameState ignorant of Telemetry preserves the "GameState
//     never directly emits to system sinks" invariant — emissions are
//     always mediated by an injected adapter.
//
// Context fields (puzzleId / mode / difficulty) are passed at construction
// because `GameStateEvent` does not carry them (intentional — the session
// itself doesn't care which puzzle it is). The composition root knows the
// puzzle and binds a fresh adapter per session.
//
// mode / difficulty are `String` (e.g. "daily" / "easy") — the caller is
// responsible for `.rawValue` conversion at the seam, per the
// TelemetryEvent.swift design note.

public import GameState

public struct GameStateTelemetryAdapter: GameStateTelemetry {
    private let telemetry: Telemetry
    private let puzzleId: String
    private let mode: String
    private let difficulty: String

    public init(
        telemetry: Telemetry,
        puzzleId: String,
        mode: String,
        difficulty: String
    ) {
        self.telemetry = telemetry
        self.puzzleId = puzzleId
        self.mode = mode
        self.difficulty = difficulty
    }

    public func dispatch(_ event: GameStateEvent) async {
        await telemetry.observe(mapping(event))
    }

    private func mapping(_ event: GameStateEvent) -> TelemetryEvent {
        switch event {
        case .sessionStarted:
            return .sessionStarted(puzzleId: puzzleId, mode: mode, difficulty: difficulty)
        case .sessionPaused:
            return .sessionPaused
        case .sessionResumed:
            return .sessionResumed
        case .sessionCompleted(let elapsedSeconds):
            return .puzzleCompleted(
                puzzleId: puzzleId,
                mode: mode,
                difficulty: difficulty,
                elapsedSeconds: elapsedSeconds
            )
        case .sessionAbandoned:
            // GameStateEvent.sessionAbandoned does not carry elapsedSeconds;
            // emit 0 — the composition root should call abandon(...) only
            // when it has separately persisted the final timer.
            return .sessionAbandoned(
                puzzleId: puzzleId,
                mode: mode,
                difficulty: difficulty,
                elapsedSeconds: 0
            )
        case .digitPlaced(let row, let col, let digit, let previous):
            return .digitPlaced(row: row, col: col, digit: digit, previous: previous)
        case .noteToggled(let row, let col, let digit, let added):
            return .noteToggled(row: row, col: col, digit: digit, added: added)
        case .moveUndone:
            return .moveUndone
        case .moveRedone:
            return .moveRedone
        }
    }
}
