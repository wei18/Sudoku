// TelemetryEvent — the canonical event surface for the Telemetry facade.
//
// M5 (issue #65) — typed payload fields:
//
// `mode` / `difficulty` payload fields are typed `Mode` / `Difficulty`
// (both from SudokuEngine). Previously they were raw `String`, which
// allowed call-site typos ("eazy", "Daily") to slip through to the
// GameCenterSink — where `leaderboardKind(forDifficulty:)` would return
// `nil` and silently drop the score. With typed enums, those typos now
// fail to compile.
//
// The original concern that this would "leak SudokuEngine into the lowest
// observability module" is resolved by the fact that `Mode` / `Difficulty`
// are zero-IO, zero-dependency String-raw enums — they carry the same
// semantic weight as primitives, with compile-time safety.

public import Foundation
public import SudokuEngine

public enum TelemetryEvent: Sendable, Equatable, Hashable, Codable {
    case digitPlaced(row: Int, col: Int, digit: Int, previous: Int?)
    case noteToggled(row: Int, col: Int, digit: Int, added: Bool)
    case moveUndone
    case moveRedone
    case sessionStarted(puzzleId: String, mode: Mode, difficulty: Difficulty)
    case sessionPaused
    case sessionResumed
    case puzzleCompleted(puzzleId: String, mode: Mode, difficulty: Difficulty, elapsedSeconds: Int)
    case sessionAbandoned(puzzleId: String, mode: Mode, difficulty: Difficulty, elapsedSeconds: Int)
    case errorOccurred(source: String, code: String, message: String)
    /// Successful Persistence save (Phase 5.4). Emitted after a SavedGame
    /// record has been persisted to CloudKit Private DB.
    case gameSaved(puzzleId: String)
    /// Failed Persistence save. `reason` is a short stable string (e.g.
    /// `"quotaExceeded"` / `"underlying"`) — not user-facing copy.
    case gameSaveFailed(puzzleId: String, reason: String)
    case metricKitReport(MetricReport)

    // MARK: - Reminder lifecycle (#287 Phase 2)
    //
    // Local-notification reminder funnel. `kind` is the stable
    // `ReminderKind.rawValue` (`"dailyReady"` / `"streakKeeper"` / `"comeback"`)
    // — passed as a plain String so this leaf observability module stays free
    // of a `Reminders` import. The host (AppComposition) owns `RemindersKit`
    // and maps `ReminderKind.rawValue` at the emit site.

    /// The soft pre-ask primer sheet was presented at a value moment (flow S03).
    case reminderPrimerShown(kind: String)
    /// The user accepted the primer → the one-shot system prompt was fired (S04).
    case reminderPrimerAccepted(kind: String)
    /// The user dismissed the primer ("Not now") — no system prompt fired (S03 self-return).
    case reminderPrimerDeclined(kind: String)
    /// A repeating reminder was scheduled (or replaced) on authorization (S04→S05).
    case reminderScheduled(kind: String)
    /// A delivered reminder presented while the app was foregrounded
    /// (`UNUserNotificationCenterDelegate.willPresent`, flow S05/S07).
    case reminderFired(kind: String)
    /// The user tapped a delivered reminder, opening the app
    /// (`UNUserNotificationCenterDelegate.didReceive`, deep-link to the Daily hub).
    case reminderOpenedApp(kind: String)
}
