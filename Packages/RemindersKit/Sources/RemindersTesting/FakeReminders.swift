// Fake conformers (proposal §4.5) for unit tests + Previews. They record every
// call and expose a scriptable status, so a test can assert
// "scheduled kind=.dailyReady with .dailyAt(9, 0)" without touching the real
// notification center. Import nothing beyond `Reminders` — no `UserNotifications`.
//
// Both are `actor`s: the protocols are `Sendable` and async, and actor isolation
// gives data-race-free recording with the least ceremony (swift6-concurrency).

public import Reminders

/// One recorded `schedule(kind:content:on:)` call.
public struct ScheduledReminder: Sendable, Equatable {
    public let kind: ReminderKind
    public let content: ReminderContent
    public let schedule: ReminderSchedule

    public init(kind: ReminderKind, content: ReminderContent, schedule: ReminderSchedule) {
        self.kind = kind
        self.content = content
        self.schedule = schedule
    }
}

/// Records scheduling calls. Mirrors the Live identifier-scoped replacement so
/// tests can assert that re-scheduling a kind replaces rather than accumulates
/// (proposal §3.2).
public actor FakeReminderScheduler: ReminderScheduler {

    /// Every `schedule` call in order (including replaced ones), for full-history
    /// assertions.
    public private(set) var scheduleCalls: [ScheduledReminder] = []

    /// Cancel calls in order.
    public private(set) var cancelCalls: [ReminderKind] = []

    /// Count of `cancelAll` calls.
    public private(set) var cancelAllCount = 0

    public init() {}

    public func schedule(kind: ReminderKind, content: ReminderContent, on schedule: ReminderSchedule) async {
        scheduleCalls.append(ScheduledReminder(kind: kind, content: content, schedule: schedule))
    }

    public func cancel(kind: ReminderKind) async {
        cancelCalls.append(kind)
    }

    public func cancelAll() async {
        cancelAllCount += 1
    }

    // MARK: - Test helpers

    /// The currently-pending reminder per kind, applying identifier-scoped
    /// replacement (last schedule wins) and removing cancelled kinds. This is the
    /// Live center's observable state, reconstructed for assertions.
    public var pending: [ReminderKind: ScheduledReminder] {
        var result: [ReminderKind: ScheduledReminder] = [:]
        for call in scheduleCalls { result[call.kind] = call }
        return result
    }
}

/// Scriptable `NotificationAuthorizing`. Set `currentStatus` / the resolved
/// status the system prompt should yield, and inspect what was requested.
public actor FakeNotificationAuthorizing: NotificationAuthorizing {

    private var status: ReminderAuthStatus

    /// The status `requestAuthorization` resolves to (defaults to `.authorized`).
    private var resolvedStatus: ReminderAuthStatus

    /// `provisional` flags passed to `requestAuthorization`, in order.
    public private(set) var requestedProvisionalFlags: [Bool] = []

    public init(status: ReminderAuthStatus = .notDetermined) {
        self.status = status
        self.resolvedStatus = .authorized
    }

    /// Script the status the next `requestAuthorization` will resolve to.
    public func setResolvedStatus(_ status: ReminderAuthStatus) {
        self.resolvedStatus = status
    }

    /// Directly script the current status (e.g. simulate a Settings change).
    public func setCurrentStatus(_ status: ReminderAuthStatus) {
        self.status = status
    }

    public func currentStatus() async -> ReminderAuthStatus { status }

    @discardableResult
    public func requestAuthorization(provisional: Bool) async -> ReminderAuthStatus {
        requestedProvisionalFlags.append(provisional)
        status = resolvedStatus
        return status
    }
}
