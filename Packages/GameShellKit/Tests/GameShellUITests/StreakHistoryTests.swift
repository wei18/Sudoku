// StreakHistoryTests — #1021 Phase A.
//
// `current`'s rule is pinned against `DailyStripLogic.computeStreak`'s
// documented behavior (`DailyStrip.swift` lines 112–124): today's own
// incompleteness never zeroes an otherwise-alive streak that ended
// yesterday.

import Foundation
import Testing
@testable import GameShellUI

@Suite("GameShellUI — StreakHistory")
struct StreakHistoryTests {

    private func day(_ string: String) throws -> DayKey {
        try #require(DayKey.key(string))
    }

    // MARK: - DayKey parsing

    @Test("DayKey parses YYYY-MM-DD")
    func dayKeyParsesWellFormedString() {
        let key = DayKey.key("2026-09-02")
        #expect(key == DayKey(year: 2026, month: 9, day: 2))
    }

    @Test("DayKey tolerates non-zero-padded components")
    func dayKeyToleratesNonZeroPadded() {
        #expect(DayKey.key("2026-9-2") == DayKey(year: 2026, month: 9, day: 2))
    }

    @Test("DayKey rejects malformed strings")
    func dayKeyRejectsMalformedStrings() {
        #expect(DayKey.key("not-a-date") == nil)
        #expect(DayKey.key("2026-09") == nil)
        #expect(DayKey.key("") == nil)
    }

    // MARK: - current: ends today / ends yesterday / broken

    @Test("current counts a run ending today")
    func currentEndingToday() throws {
        let today = try day("2026-09-02")
        let history = StreakHistory(
            completedDays: [today, try day("2026-09-01"), try day("2026-08-31")],
            today: today
        )
        #expect(history.current == 3)
    }

    @Test("current counts a run ending yesterday when today isn't completed yet")
    func currentEndingYesterday() throws {
        let today = try day("2026-09-02")
        let history = StreakHistory(
            completedDays: [try day("2026-09-01"), try day("2026-08-31")],
            today: today
        )
        #expect(history.current == 2)
    }

    @Test("current is zero when the run is broken before yesterday")
    func currentBrokenBeforeYesterday() throws {
        let today = try day("2026-09-02")
        let history = StreakHistory(
            completedDays: [try day("2026-08-31")], // gap at 09-01 (yesterday)
            today: today
        )
        #expect(history.current == 0)
    }

    // MARK: - longest: independent of the run touching today

    @Test("longest finds the longest run even when it doesn't touch today")
    func longestFindsIsolatedRun() throws {
        let today = try day("2026-09-02")
        let history = StreakHistory(
            completedDays: [
                try day("2026-08-20"), try day("2026-08-21"), try day("2026-08-22"), // run of 3
                try day("2026-08-30"), try day("2026-08-31"), // run of 2
            ],
            today: today
        )
        #expect(history.longest == 3)
        #expect(history.current == 0) // today and yesterday (09-01) both incomplete
    }

    // MARK: - last7: oldest → newest, ending today

    @Test("last7 orders oldest to newest and ends on today")
    func last7OrderingEndsToday() throws {
        let today = try day("2026-09-02")
        let history = StreakHistory(
            completedDays: [try day("2026-08-30"), try day("2026-08-31")],
            today: today
        )
        // 08-27, 08-28, 08-29, 08-30, 08-31, 09-01, 09-02
        #expect(history.last7 == [false, false, false, true, true, false, false])
    }

    // MARK: - monthCells: leading offset for a month starting on Wednesday

    @Test("monthCells leads with the right blank count for a month starting on Wednesday")
    func monthCellsLeadingOffsetForWednesdayStart() throws {
        // Verified via `date -j -f "%Y-%m-%d" 2026-04-01 "+%A"` → Wednesday.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = 1 // Sunday-first

        let today = try day("2026-09-02")
        let history = StreakHistory(completedDays: [], today: today)
        let cells = history.monthCells(for: DayKey(year: 2026, month: 4, day: 1), calendar: calendar)

        // Sunday-first grid, 1st is Wednesday → 3 leading blanks (Sun, Mon, Tue).
        #expect(cells.prefix(3).allSatisfy { $0.day == nil })
        #expect(cells[3].day == 1)
        // April has 30 days.
        #expect(cells.count == 3 + 30)
        #expect(cells.last?.day == 30)
    }

    @Test("monthCells marks completed days and today")
    func monthCellsMarksCompletedAndToday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.firstWeekday = 1

        let today = try day("2026-09-02")
        let history = StreakHistory(completedDays: [try day("2026-09-01")], today: today)
        let cells = history.monthCells(for: DayKey(year: 2026, month: 9, day: 1), calendar: calendar)

        let dayOne = cells.first { $0.day == 1 }
        #expect(dayOne?.isCompleted == true)
        let dayTwo = cells.first { $0.day == 2 }
        #expect(dayTwo?.isToday == true)
        #expect(dayTwo?.isCompleted == false)
    }
}
