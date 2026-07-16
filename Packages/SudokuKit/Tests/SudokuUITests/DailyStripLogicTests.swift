// DailyStripLogicTests — #774 pure streak-computation matrix.
//
// `DailyStripLogic.computeStreak` has no CloudKit / MainActor dependency —
// these tests exercise it directly over hand-built `DailyStripDay` arrays,
// covering the dispatch spec's matrix: empty, today-only,
// chain-ending-yesterday-today-incomplete, chain-with-gap, 7+ (window-capped).

import Foundation
import Testing
@testable import SudokuUI

@Suite("DailyStripLogic — streak computation (#774)")
struct DailyStripLogicTests {

    private static let referenceDate = Date(timeIntervalSince1970: 1_715_000_000)

    /// Builds a 7-day window (oldest `offset:6` → newest `offset:0`=today)
    /// from a completion flag list ordered the same way, e.g.
    /// `days(completed: [false, false, false, false, false, false, false])`
    /// is an empty week; the LAST element is always today.
    private func days(completed: [Bool]) -> [DailyStripDay] {
        precondition(completed.count == 7)
        return completed.enumerated().map { index, isCompleted in
            let offset = 6 - index
            let date = Self.referenceDate.addingTimeInterval(-Double(offset) * 86_400)
            return DailyStripDay(offsetFromToday: offset, date: date, isCompleted: isCompleted)
        }
    }

    @Test func emptyWeekIsZeroStreak() {
        let week = days(completed: [false, false, false, false, false, false, false])
        #expect(DailyStripLogic.computeStreak(days: week) == 0)
    }

    @Test func todayOnlyIsOneDayStreak() {
        let week = days(completed: [false, false, false, false, false, false, true])
        #expect(DailyStripLogic.computeStreak(days: week) == 1)
    }

    /// Today is NOT yet completed but yesterday (and the day before) are —
    /// today's incompleteness must not zero out the alive chain ending
    /// yesterday.
    @Test func chainEndingYesterdayIsNotZeroedByTodaysIncompleteness() {
        let week = days(completed: [false, false, false, false, true, true, false])
        #expect(DailyStripLogic.computeStreak(days: week) == 2)
    }

    /// A gap 2 days back stops the count even though there is a longer chain
    /// further back — only the CONSECUTIVE run counts.
    @Test func chainWithGapStopsAtTheGap() {
        let week = days(completed: [true, true, true, true, false, true, true])
        #expect(DailyStripLogic.computeStreak(days: week) == 2)
    }

    /// Every day in the 7-day window completed — the fetch window itself
    /// caps what can be proven; the raw count saturates at the window size.
    @Test func fullWindowSaturatesAtWindowSize() {
        let week = days(completed: [true, true, true, true, true, true, true])
        #expect(DailyStripLogic.computeStreak(days: week) == 7)
    }

    @Test func emptyDaysArrayIsZeroStreak() {
        #expect(DailyStripLogic.computeStreak(days: []) == 0)
    }
}
