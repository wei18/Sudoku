// RecurrenceStartDateTests — verify `LeaderboardConfig.currentRecurrenceStartDateUTC`
// emits the literal ISO 8601 datetime shape ASC expects for the required
// `recurrenceStartDate` attribute (§How.3.1 / issue #22).
//
// Shape: `yyyy-MM-dd'T'00:00:00Z` — POSIX locale, UTC timezone, no fractional
// seconds, no `+00:00` offset variants. If ASC round 4 rejects this shape,
// see impl-notes §未決 #1 for fallback candidates.

internal import Foundation
internal import Testing
@testable import ASCRegister

@Suite("Recurrence start date")
internal struct RecurrenceStartDateTests {

    @Test("UTC midnight on a given day formats as yyyy-MM-dd'T'00:00:00Z")
    internal func formatsUTCMidnight() {
        // 2026-05-20 12:34:56 UTC → should floor to 2026-05-20T00:00:00Z.
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 5
        comps.day = 20
        comps.hour = 12
        comps.minute = 34
        comps.second = 56
        comps.timeZone = TimeZone(identifier: "UTC")
        var calendar = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // swiftlint:disable:next force_unwrapping
        let now = calendar.date(from: comps)!

        let out = LeaderboardConfig.currentRecurrenceStartDateUTC(at: now)
        #expect(out == "2026-05-20T00:00:00Z")
    }

    @Test("Already-midnight UTC input round-trips unchanged")
    internal func midnightUTCRoundTrip() {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 1
        comps.day = 1
        comps.timeZone = TimeZone(identifier: "UTC")
        var calendar = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // swiftlint:disable:next force_unwrapping
        let now = calendar.date(from: comps)!

        let out = LeaderboardConfig.currentRecurrenceStartDateUTC(at: now)
        #expect(out == "2026-01-01T00:00:00Z")
    }

    @Test("Late-night UTC stays on the same day (no off-by-one)")
    internal func lateNightUTC() {
        // 2026-12-31 23:59:59 UTC → still 2026-12-31, not rolled to 2027-01-01.
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 12
        comps.day = 31
        comps.hour = 23
        comps.minute = 59
        comps.second = 59
        comps.timeZone = TimeZone(identifier: "UTC")
        var calendar = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // swiftlint:disable:next force_unwrapping
        let now = calendar.date(from: comps)!

        let out = LeaderboardConfig.currentRecurrenceStartDateUTC(at: now)
        #expect(out == "2026-12-31T00:00:00Z")
    }
}
