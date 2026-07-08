// MinesweeperDailyStreakMath — pure consecutive-day streak counting (#700).
//
// Mirrors Sudoku's `AchievementEvaluator.consecutiveDailyStreak` shape, but
// decoupled from Persistence: the caller supplies the already-fetched set of
// UTC day-strings (`UTCDay.string(from:)` shape, `"YYYY-MM-DD"`) that had at
// least one daily win, and this function just counts backward from `today`.
// Kept standalone (not folded into the evaluator) so the day-arithmetic can
// be unit-tested directly with plain string/date literals.

public import Foundation
public import MinesweeperGameState

public enum MinesweeperDailyStreakMath {

    /// Number of consecutive UTC days, ending on `today` and counting
    /// backward, present in `dailyWinDays`. Stops at the first missing day.
    /// Capped at `maxDays` (30 covers both `daily.streak_7` and
    /// `daily.streak_30`).
    public static func consecutiveStreak(
        dailyWinDays: Set<String>,
        endingOn today: Date,
        maxDays: Int = 30
    ) -> Int {
        var streak = 0
        for offset in 0..<maxDays {
            guard let day = utcDay(offsetFrom: today, byDays: -offset) else { break }
            guard dailyWinDays.contains(UTCDay.string(from: day)) else { break }
            streak += 1
        }
        return streak
    }

    private static func utcDay(offsetFrom anchor: Date, byDays days: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar.date(byAdding: .day, value: days, to: anchor)
    }
}
