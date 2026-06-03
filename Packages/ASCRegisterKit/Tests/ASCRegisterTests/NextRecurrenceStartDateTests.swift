// NextRecurrenceStartDateTests — verify `LeaderboardConfig.nextRecurrenceStartDateUTC`
// emits a strictly-future UTC midnight in ISO 8601 datetime shape, per ASC's
// round-5 contract requirement that `recurrenceStartDate` must not be in the
// past (§How.3.1 / issue #26).
//
// Shape: `yyyy-MM-dd'T'00:00:00Z` — POSIX locale, UTC timezone, no fractional
// seconds, no `+00:00` offset variants. Value: the next UTC 00:00 strictly
// after the supplied instant.

internal import Foundation
internal import Testing
@testable import ASCRegister

@Suite("Next recurrence start date")
internal struct NextRecurrenceStartDateTests {

    /// Build a UTC `Date` from explicit components.
    private static func utcDate(
        year: Int, month: Int, day: Int,
        hour: Int = 0, minute: Int = 0, second: Int = 0
    ) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        comps.timeZone = TimeZone(identifier: "UTC")
        var calendar = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // swiftlint:disable:next force_unwrapping
        return calendar.date(from: comps)!
    }

    @Test("Mid-day UTC rolls to next-day UTC midnight")
    internal func midDayRollsToTomorrow() {
        // 2026-05-20 12:30:00 UTC → 2026-05-21T00:00:00Z
        let now = Self.utcDate(year: 2026, month: 5, day: 20, hour: 12, minute: 30)
        let out = LeaderboardConfig.nextRecurrenceStartDateUTC(at: now)
        #expect(out == "2026-05-21T00:00:00Z")
    }

    @Test("Exact UTC midnight rolls forward (strict future, not equal)")
    internal func exactMidnightRollsForward() {
        // 2026-05-20 00:00:00 UTC → 2026-05-21T00:00:00Z (NOT same day).
        let now = Self.utcDate(year: 2026, month: 5, day: 20)
        let out = LeaderboardConfig.nextRecurrenceStartDateUTC(at: now)
        #expect(out == "2026-05-21T00:00:00Z")
    }

    @Test("Late-night UTC rolls to next-day midnight (no off-by-one)")
    internal func lateNightRollsToTomorrow() {
        // 2026-05-20 23:59:59 UTC → 2026-05-21T00:00:00Z
        let now = Self.utcDate(year: 2026, month: 5, day: 20, hour: 23, minute: 59, second: 59)
        let out = LeaderboardConfig.nextRecurrenceStartDateUTC(at: now)
        #expect(out == "2026-05-21T00:00:00Z")
    }

    @Test("Month boundary: last second of month rolls to next month")
    internal func monthBoundary() {
        // 2026-12-31 23:59:59 UTC → 2027-01-01T00:00:00Z
        let now = Self.utcDate(year: 2026, month: 12, day: 31, hour: 23, minute: 59, second: 59)
        let out = LeaderboardConfig.nextRecurrenceStartDateUTC(at: now)
        #expect(out == "2027-01-01T00:00:00Z")
    }

    @Test("Returned instant is strictly after the input Date")
    internal func strictlyFuture() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // swiftlint:disable:next force_unwrapping
        formatter.timeZone = TimeZone(identifier: "UTC")!
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"

        let inputs: [Date] = [
            Self.utcDate(year: 2026, month: 5, day: 20, hour: 12, minute: 30),
            Self.utcDate(year: 2026, month: 5, day: 20),
            Self.utcDate(year: 2026, month: 5, day: 20, hour: 23, minute: 59, second: 59),
            Self.utcDate(year: 2026, month: 12, day: 31, hour: 23, minute: 59, second: 59)
        ]
        for input in inputs {
            let outString = LeaderboardConfig.nextRecurrenceStartDateUTC(at: input)
            // swiftlint:disable:next force_unwrapping
            let outDate = formatter.date(from: outString)!
            #expect(outDate > input, "expected \(outString) > \(input)")
        }
    }
}
