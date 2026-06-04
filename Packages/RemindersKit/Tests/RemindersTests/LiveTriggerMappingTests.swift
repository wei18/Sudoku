// Live trigger-type coverage for `LiveReminderScheduler` (GitHub #319; #287 CR
// nit N1). The schedule → `UNNotificationTrigger` mapping is contract-bearing
// (proposal §3.1 / §4.4) but the production mapping is otherwise private and was
// untested because the full `schedule(...)` path needs the system
// `UNUserNotificationCenter`.
//
// Seam: `LiveReminderScheduler.trigger(for:)` is a pure, `static`, self-free
// mapping exposed `internal` and reached here via `@testable import Reminders`,
// so we assert the trigger SUBTYPE + key params without the system center.

import Foundation
import Testing
import UserNotifications

@testable import Reminders

@Suite("LiveReminderScheduler — schedule → trigger mapping")
struct LiveTriggerMappingTests {

    @Test(".dailyAt maps to a repeating UNCalendarNotificationTrigger with hour/minute")
    func dailyAtMapsToRepeatingCalendarTrigger() throws {
        let trigger = LiveReminderScheduler.trigger(for: .dailyAt(hour: 9, minute: 30))

        let calendar = try #require(trigger as? UNCalendarNotificationTrigger)
        #expect(calendar.repeats == true)
        #expect(calendar.dateComponents.hour == 9)
        #expect(calendar.dateComponents.minute == 30)
        // dailyAt fixes only time-of-day — no day/month anchoring.
        #expect(calendar.dateComponents.day == nil)
        #expect(calendar.dateComponents.month == nil)
    }

    @Test(".after maps to a non-repeating UNTimeIntervalNotificationTrigger with the interval")
    func afterMapsToTimeIntervalTrigger() throws {
        let trigger = LiveReminderScheduler.trigger(for: .after(seconds: 86_400))

        let interval = try #require(trigger as? UNTimeIntervalNotificationTrigger)
        #expect(interval.repeats == false)
        #expect(interval.timeInterval == 86_400)
    }

    @Test(".onDate maps to a one-shot (non-repeating) UNCalendarNotificationTrigger")
    func onDateMapsToOneShotCalendarTrigger() throws {
        var components = DateComponents()
        components.year = 2_026
        components.month = 12
        components.day = 25
        components.hour = 8

        let trigger = LiveReminderScheduler.trigger(for: .onDate(components))

        let calendar = try #require(trigger as? UNCalendarNotificationTrigger)
        #expect(calendar.repeats == false)
        #expect(calendar.dateComponents.year == 2_026)
        #expect(calendar.dateComponents.month == 12)
        #expect(calendar.dateComponents.day == 25)
        #expect(calendar.dateComponents.hour == 8)
    }

    @Test(".dailyAt and .onDate are distinguished only by the repeats flag")
    func dailyAtAndOnDateDifferByRepeatsFlag() {
        let daily = LiveReminderScheduler.trigger(for: .dailyAt(hour: 7, minute: 0))
            as? UNCalendarNotificationTrigger
        let onDate = LiveReminderScheduler.trigger(for: .onDate(DateComponents()))
            as? UNCalendarNotificationTrigger

        #expect(daily?.repeats == true)
        #expect(onDate?.repeats == false)
    }
}
