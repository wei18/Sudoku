// StreakHistory — pure streak/calendar math backing PROGRESS's streak
// calendar and TODAY's streak header (#1021 Phase A, design.md §3.3).
//
// `DayKey.key(_:)` parses the exact `"YYYY-MM-DD"` UTC format
// `PersistenceProtocol.swift`'s `fetchCompletedDailyIdsByDay` documents its
// dictionary keys as (`SavedGameStore.extractDailyDay`'s format) — the shell
// never sees a `Date` from persistence for this data, only these strings.
//
// `current`'s rule mirrors `DailyStripLogic.computeStreak` (`DailyStrip.swift`
// lines 112–124) EXACTLY: walk back from today if today is completed, else
// from yesterday, stopping at the first gap — today's own incompleteness
// never zeroes an otherwise-alive streak that ended yesterday.

public import Foundation

/// A calendar day, `Sendable`/`Hashable`/`Comparable` on its own (no `Date`,
/// no timezone ambiguity once constructed) so it can be a `Set` key and a
/// `Dictionary`-free lookup target.
public struct DayKey: Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = components.year ?? 0
        self.month = components.month ?? 0
        self.day = components.day ?? 0
    }

    /// Parses persistence's `"YYYY-MM-DD"` key format. Malformed input
    /// degrades to `nil` rather than trapping — matches `BoardPreview.init?`'s
    /// convention for per-app data the shell doesn't control.
    public static func key(_ string: String) -> DayKey? {
        let parts = string.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        return DayKey(year: year, month: month, day: day)
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// UTC noon round-trip through `Date` sidesteps DST — this type carries
    /// no time-of-day, only a calendar day, so "noon" is an arbitrary but
    /// always-safe anchor.
    var previousDay: DayKey { adding(days: -1) }
    var nextDay: DayKey { adding(days: 1) }

    private func adding(days: Int) -> DayKey {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        guard let anchor = calendar.date(from: components),
              let shifted = calendar.date(byAdding: .day, value: days, to: anchor)
        else { return self }
        return DayKey(shifted, calendar: calendar)
    }
}

/// One cell in a month grid. `day == nil` is a leading blank (before the
/// month's first day lands on its weekday column).
public struct MonthCell: Sendable, Equatable {
    public let day: Int?
    public let isCompleted: Bool
    public let isToday: Bool

    public init(day: Int?, isCompleted: Bool, isToday: Bool) {
        self.day = day
        self.isCompleted = isCompleted
        self.isToday = isToday
    }
}

// `Equatable` (#1021 Phase D, additive): PROGRESS's `ProgressModel` needs to
// compare two `StreakHistory` values (SwiftUI's re-render diffing), and both
// stored properties (`Set<DayKey>`, `DayKey`) are already `Equatable` on
// their own — synthesis costs nothing here.
public struct StreakHistory: Sendable, Equatable {
    private let completedDays: Set<DayKey>
    public let today: DayKey

    public init(completedDays: Set<DayKey>, today: DayKey) {
        self.completedDays = completedDays
        self.today = today
    }

    /// Consecutive completed days ending TODAY, or — if today isn't
    /// completed (yet) — ending YESTERDAY. See file header: mirrors
    /// `DailyStripLogic.computeStreak`'s rule exactly.
    public var current: Int {
        var cursor = today
        if !completedDays.contains(cursor) {
            cursor = cursor.previousDay
        }
        var streak = 0
        while completedDays.contains(cursor) {
            streak += 1
            cursor = cursor.previousDay
        }
        return streak
    }

    /// Longest consecutive run anywhere in `completedDays`, not just the one
    /// ending at `today`. Each day is visited at most twice (once as a
    /// candidate run-start check, once inside its own run's forward walk).
    public var longest: Int {
        var best = 0
        for day in completedDays where !completedDays.contains(day.previousDay) {
            var run = 0
            var cursor = day
            while completedDays.contains(cursor) {
                run += 1
                cursor = cursor.nextDay
            }
            best = max(best, run)
        }
        return best
    }

    /// Oldest → newest, ending today.
    public var last7: [Bool] {
        var days: [Bool] = []
        var cursor = today
        for _ in 0..<7 {
            days.append(completedDays.contains(cursor))
            cursor = cursor.previousDay
        }
        return days.reversed()
    }

    /// Leading `nil`-day blanks (weekday offset of the 1st) + one cell per
    /// day of `month`. `calendar.firstWeekday` (1 = Sunday by default)
    /// decides which column the grid starts on.
    public func monthCells(for month: DayKey, calendar: Calendar = .current) -> [MonthCell] {
        var components = DateComponents()
        components.year = month.year
        components.month = month.month
        components.day = 1
        components.hour = 12
        guard let firstOfMonth = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: firstOfMonth)
        else { return [] }

        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7

        var cells = Array(repeating: MonthCell(day: nil, isCompleted: false, isToday: false), count: leadingBlanks)
        for dayNumber in range {
            let key = DayKey(year: month.year, month: month.month, day: dayNumber)
            cells.append(MonthCell(day: dayNumber, isCompleted: completedDays.contains(key), isToday: key == today))
        }
        return cells
    }
}
