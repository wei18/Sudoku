// UTCDayTests — format + UTC-rollover coverage for the shared day-bucket key (#305).
//
// Pins the contract both game cores rely on: a `Date` formats to a stable
// `"YYYY-MM-DD"` interpreted in UTC, rolling over exactly at UTC midnight
// regardless of the device timezone. Equivalent coverage was previously only
// exercised transitively (Sudoku) and inside MinesweeperDailyTests (#290);
// it now lives with the type.

import Foundation
import Testing
@testable import TimeKit

// MARK: - Date helpers (UTC)

private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    // swiftlint:disable:next force_unwrapping
    return calendar.date(from: components)!
}

@Suite struct UTCDayTests {

    // MARK: Format

    @Test func formatsAsZeroPaddedYearMonthDay() {
        #expect(UTCDay.string(from: utcDate(2026, 6, 5)) == "2026-06-05")
        #expect(UTCDay.string(from: utcDate(1, 1, 1)) == "0001-01-01")
        #expect(UTCDay.string(from: utcDate(2026, 12, 31)) == "2026-12-31")
    }

    // MARK: UTC interpretation — time of day does not change the bucket

    @Test func sameDayDifferentTimesBucketIdentically() {
        let morning = utcDate(2026, 6, 4, 0, 1)
        let evening = utcDate(2026, 6, 4, 23, 59)
        #expect(UTCDay.string(from: morning) == "2026-06-04")
        #expect(UTCDay.string(from: evening) == "2026-06-04")
    }

    // MARK: Rollover boundary — exact UTC midnight

    @Test func midnightBoundaryIsExact() {
        // 23:59 of day N buckets to day N; 00:00 of day N+1 buckets to N+1.
        let justBefore = utcDate(2026, 6, 4, 23, 59)
        let justAfter = utcDate(2026, 6, 5, 0, 0)
        #expect(UTCDay.string(from: justBefore) == "2026-06-04")
        #expect(UTCDay.string(from: justAfter) == "2026-06-05")
    }
}
