// LiveReminderScheduler — the production `ReminderScheduler`, wrapping
// `UNUserNotificationCenter.current()`.
//
// RESTRICTED IMPORT: one of the only two files allowed to import
// `UserNotifications` (the other is LiveNotificationAuthorizer). See proposal §4.5.
//
// Scheduling discipline (proposal §3.2 — the 64-limit / async-race rule):
//   schedule = removePendingNotificationRequests(withIdentifiers: [id]) then add(_:)
// NEVER `removeAllPendingNotificationRequests` on the schedule path — that runs on
// a background thread and can race-delete a just-added request. Each `ReminderKind`
// owns one stable identifier (`kind.rawValue`), so replace-in-place is correct.

internal import Foundation
internal import UserNotifications
internal import os

public struct LiveReminderScheduler: ReminderScheduler {

    private let logger: Logger

    // `UNUserNotificationCenter.current()` is a singleton accessor and is NOT
    // `Sendable`, so we fetch it per call rather than store it — this keeps the
    // struct trivially `Sendable` without `@unchecked`.
    private var center: UNUserNotificationCenter { .current() }

    /// - Parameters:
    ///   - subsystem: OSLog subsystem — pass the host app's bundle id
    ///     (oslog-logger-defaults).
    public init(subsystem: String) {
        self.logger = Logger(subsystem: subsystem, category: "Reminders")
    }

    // TELEMETRY SEAM (Phase 2, proposal §4.6): this target does NOT import
    // `Telemetry`. The host composition root observes scheduling outcomes and
    // calls `telemetry.observe(.reminderScheduled(kind:))`. No callback is wired
    // in the foundation — left as a documented seam.

    public func schedule(kind: ReminderKind, content: ReminderContent, on schedule: ReminderSchedule) async {
        let identifier = kind.rawValue

        // Identifier-scoped replacement — never removeAll (§3.2).
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let request = UNNotificationRequest(
            identifier: identifier,
            content: makeContent(content),
            trigger: makeTrigger(schedule)
        )
        do {
            try await center.add(request)
            logger.debug("scheduled reminder \(identifier, privacy: .public)")
        } catch {
            logger.error("schedule \(identifier, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func cancel(kind: ReminderKind) async {
        center.removePendingNotificationRequests(withIdentifiers: [kind.rawValue])
    }

    public func hasPending(kind: ReminderKind) async -> Bool {
        await center.pendingNotificationRequests()
            .contains { $0.identifier == kind.rawValue }
    }

    public func cancelAll() async {
        // Scoped to OUR known kind identifiers — not a system-wide removeAll (§3.4).
        center.removePendingNotificationRequests(
            withIdentifiers: ReminderKind.allCases.map(\.rawValue)
        )
    }

    // MARK: - Mapping

    private func makeContent(_ content: ReminderContent) -> UNMutableNotificationContent {
        let mutable = UNMutableNotificationContent()
        mutable.title = content.title
        mutable.body = content.body
        if content.sound { mutable.sound = .default }
        if let categoryId = content.categoryId { mutable.categoryIdentifier = categoryId }
        return mutable
    }

    private func makeTrigger(_ schedule: ReminderSchedule) -> UNNotificationTrigger {
        Self.trigger(for: schedule)
    }

    // Pure schedule → trigger mapping. `static` + self-free so it is exercisable
    // without the system `UNUserNotificationCenter` — the testable seam for the
    // contract-bearing mapping (GitHub #319, #287 CR nit N1). `internal` so
    // `@testable import Reminders` can assert each case's trigger subtype + key
    // params. Behavior is identical to the inlined switch it replaced.
    internal static func trigger(for schedule: ReminderSchedule) -> UNNotificationTrigger {
        switch schedule {
        case let .dailyAt(hour, minute):
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        case let .after(seconds):
            return UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)

        case let .onDate(components):
            return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }
    }
}
