// Noop conformers (proposal §4.5). Production-safe no-ops for apps / platforms
// not yet wiring reminders (e.g. Minesweeper has no Daily; macOS if deferred) and
// for SwiftUI Previews. Import nothing — pure protocol satisfaction.

/// Reports `.notDetermined`; requesting authorization is a no-op that returns the
/// requested-neutral `.notDetermined` (nothing is ever prompted).
public struct NoopNotificationAuthorizing: NotificationAuthorizing {

    public init() {}

    public func currentStatus() async -> ReminderAuthStatus { .notDetermined }

    @discardableResult
    public func requestAuthorization(provisional: Bool) async -> ReminderAuthStatus {
        .notDetermined
    }
}

/// Drops every scheduling call on the floor.
public struct NoopReminderScheduler: ReminderScheduler {

    public init() {}

    public func schedule(kind: ReminderKind, content: ReminderContent, on schedule: ReminderSchedule) async {}

    public func cancel(kind: ReminderKind) async {}

    public func cancelAll() async {}

    public func hasPending(kind: ReminderKind) async -> Bool { false }
}
