// UTCDay — UTC calendar-day formatter for daily-puzzle bucketing.
//
// Mirrors `SudokuCoreKit/Sources/SudokuEngine/UTCDay.swift` (the Sudoku core's
// shared day-bucket key). Minimally re-implemented here rather than imported:
// SudokuEngine is a Sudoku-specific package, so MinesweeperEngine depending on
// it would introduce a wrong-direction cross-game coupling. The algorithm is
// byte-for-byte identical so both games bucket UTC days the same way.
//
// → Future shared-extraction candidate: a `TimeKit`/`CalendarKit` leaf both
//   game cores depend on. Tracked in foundations.md §Backlog.

public import Foundation

/// Format a `Date` as `"YYYY-MM-DD"` in UTC — the stable per-day key the
/// daily puzzle seed is derived from (same date → same board everywhere,
/// rolling over at UTC midnight regardless of device timezone).
public enum UTCDay {

    /// Gregorian calendar pinned to UTC. `TimeZone(identifier: "UTC")` is
    /// documented to never return nil for the literal `"UTC"` identifier, but
    /// we fall back to `.gmt` (a non-optional constant) instead of
    /// force-unwrapping — same observable behaviour.
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
