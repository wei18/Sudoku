// MinesweeperDailyStreakMathTests — pure day-arithmetic coverage (#700).

import Foundation
import Testing
@testable import MinesweeperUI

@Suite("MinesweeperDailyStreakMath")
struct MinesweeperDailyStreakMathTests {

    /// UTC midnight for a "YYYY-MM-DD" literal, used to build `today` anchors.
    private func utcDate(_ yyyyMMdd: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let comps = yyyyMMdd.split(separator: "-").map { Int($0)! }
        return calendar.date(from: DateComponents(year: comps[0], month: comps[1], day: comps[2]))!
    }

    @Test("Consecutive days ending today count up correctly")
    func consecutiveDaysCountUp() {
        let days: Set<String> = ["2026-07-05", "2026-07-06", "2026-07-07", "2026-07-08"]
        let streak = MinesweeperDailyStreakMath.consecutiveStreak(dailyWinDays: days, endingOn: utcDate("2026-07-08"))
        #expect(streak == 4)
    }

    @Test("A gap breaks the streak — only days counting backward from today matter")
    func gapBreaksStreak() {
        // Missing 07-07: today (08) + yesterday would need 07, but 07 is absent.
        let days: Set<String> = ["2026-07-08", "2026-07-06", "2026-07-05"]
        let streak = MinesweeperDailyStreakMath.consecutiveStreak(dailyWinDays: days, endingOn: utcDate("2026-07-08"))
        #expect(streak == 1)
    }

    @Test("No win today yields a streak of 0, even with a long run ending yesterday")
    func noWinTodayYieldsZero() {
        let days: Set<String> = ["2026-07-07", "2026-07-06", "2026-07-05"]
        let streak = MinesweeperDailyStreakMath.consecutiveStreak(dailyWinDays: days, endingOn: utcDate("2026-07-08"))
        #expect(streak == 0)
    }

    @Test("Empty day set yields a streak of 0")
    func emptySetYieldsZero() {
        let streak = MinesweeperDailyStreakMath.consecutiveStreak(dailyWinDays: [], endingOn: utcDate("2026-07-08"))
        #expect(streak == 0)
    }

    @Test("Streak caps at maxDays even with an unbroken longer run")
    func capsAtMaxDays() {
        var days: Set<String> = []
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = utcDate("2026-07-08")
        for offset in 0..<40 {
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            days.insert(Self.string(from: day))
        }
        let streak = MinesweeperDailyStreakMath.consecutiveStreak(dailyWinDays: days, endingOn: today, maxDays: 30)
        #expect(streak == 30)
    }

    private static func string(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }
}
