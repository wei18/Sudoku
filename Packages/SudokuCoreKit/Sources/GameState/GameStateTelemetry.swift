// GameStateTelemetry — local protocol seam for telemetry dispatch.
//
// DESIGN NOTE (Phase 3 vs Phase 4):
//
// Phase 4 introduces the real `Telemetry` actor + `TelemetrySink` protocol.
// Phase 3 cannot depend on that module yet (it's intentionally orderable
// AFTER Phase 3 per plan.md), so we declare a LOCAL protocol seam here.
// Phase 4 will:
//
//   1. Implement a `GameStateTelemetryAdapter: GameStateTelemetry` inside
//      the Telemetry module that wraps `Telemetry.observe(_:)`, OR
//   2. Refactor GameState to depend on Telemetry directly and delete this
//      file, mapping `GameStateEvent` cases to `TelemetryEvent` cases.
//
// Either way, `GameSession.init(... telemetry:)` keeps the same signature
// shape — only the concrete adapter changes.

import Foundation

public protocol GameStateTelemetry: Sendable {
    func dispatch(_ event: GameStateEvent) async
}

/// Events emitted by GameSession. All payload values are pure data — no
/// references to actors or live system clocks — so this enum is freely
/// Sendable + Equatable for test assertions.
public enum GameStateEvent: Sendable, Equatable, Hashable {
    case sessionStarted
    case sessionPaused
    case sessionResumed
    case sessionCompleted(elapsedSeconds: Int)
    case sessionAbandoned
    case digitPlaced(row: Int, col: Int, digit: Int, previous: Int?)
    case noteToggled(row: Int, col: Int, digit: Int, added: Bool)
    case moveUndone
    case moveRedone
}

/// Default sink — discards every event. Used when callers don't wire a
/// real telemetry pipeline (e.g. unit tests of features that don't care
/// about events).
public struct NoOpGameStateTelemetry: GameStateTelemetry {
    public init() {}
    public func dispatch(_ event: GameStateEvent) async {}
}
