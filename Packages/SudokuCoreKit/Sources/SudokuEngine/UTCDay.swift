// UTCDay — shared UTC calendar-day formatter (Wave 3 audit M16 refactor).
//
// `puzzleId` / leaderboard / streak / SavedGame queries all key off the
// same `"YYYY-MM-DD"` string interpreted in UTC. Prior to this extraction
// the same Calendar+TimeZone+DateComponents block was duplicated across
// `PuzzleStore.PuzzleIdentity`, `SubmitGuards`, `AchievementEvaluator`
// and `SavedGameStore`, each carrying its own
// `// swiftlint:disable force_unwrapping` for the `TimeZone(identifier:
// "UTC")!` lookup. Co-located here in SudokuEngine — the deepest leaf —
// so every caller (PuzzleStore / GameCenterClient / Persistence) can
// reach it through its existing dependency chain.

public import Foundation

/// Format a `Date` as `"YYYY-MM-DD"` in UTC.
///
/// Use this anywhere a stable day-bucket key is needed regardless of the
/// device timezone — puzzleId day prefix, leaderboard cross-day guard,
/// daily-completion streak counting, CloudKit dailyCompletedOn query.
public enum UTCDay {

    /// Gregorian calendar pinned to UTC. `TimeZone(identifier: "UTC")` is
    /// documented to never return nil for the literal `"UTC"` identifier,
    /// but we still fall back to `.gmt` (a non-optional constant) instead
    /// of force-unwrapping — same observable behaviour with no swiftlint
    /// disable required.
    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// Format `date` as `"YYYY-MM-DD"` in UTC.
    public static func string(from date: Date) -> String {
        let components = utcCalendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
