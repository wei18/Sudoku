// TelemetryEvent — the canonical event surface for the Telemetry facade.
//
// DESIGN NOTE — primitive payload fields instead of mirror enums:
//
// plan.md §4.1 originally specified mirror `Difficulty` / `GameMode` types
// living inside the Telemetry target. We deliberately deviate: payloads carry
// raw `String` values (e.g. `mode: "daily"`, `difficulty: "easy"`) and callers
// at the adapter seam perform `.rawValue` conversion. Rationale:
//
// - Telemetry should not depend on SudokuEngine (where `Difficulty` lives) —
//   doing so would make the lowest-level observability module pull in the
//   pure-domain core.
// - Shipping a duplicate `Difficulty` definition inside Telemetry invites
//   silent drift between two truths.
//
// The narrow seam is `GameStateTelemetryAdapter` (this target) which performs
// the string conversion exactly once.

import Foundation

public enum TelemetryEvent: Sendable, Equatable, Hashable, Codable {
    case digitPlaced(row: Int, col: Int, digit: Int, previous: Int?)
    case noteToggled(row: Int, col: Int, digit: Int, added: Bool)
    case moveUndone
    case moveRedone
    case sessionStarted(puzzleId: String, mode: String, difficulty: String)
    case sessionPaused
    case sessionResumed
    case puzzleCompleted(puzzleId: String, mode: String, difficulty: String, elapsedSeconds: Int)
    case sessionAbandoned(puzzleId: String, mode: String, difficulty: String, elapsedSeconds: Int)
    case errorOccurred(source: String, code: String, message: String)
    case metricKitReport(MetricReport)
}
