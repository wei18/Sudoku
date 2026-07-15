// The two protocol seams (proposal §4.4). Wrapping the awkward-to-fake
// `UNUserNotificationCenter` behind protocols lets UI / logic / tests depend on
// abstractions and swap Live ↔ Noop ↔ Fake (swift-testing-baseline
// protocol-injected fakes). `UserNotifications` is imported only by the Live
// conformers, never here.

/// Seam 1 — permission. Wraps `UNUserNotificationCenter` authorization +
/// settings read-back.
public protocol NotificationAuthorizing: Sendable {

    /// Re-read the current status (the user can change it in Settings at any
    /// time — proposal §5.1 step 6).
    func currentStatus() async -> ReminderAuthStatus

    /// Fire the one-and-only system prompt. `provisional: true` requests quiet
    /// provisional authorization (no upfront prompt); `false` requests explicit
    /// `.alert + .sound` (proposal §5.2). Returns the resolved status.
    @discardableResult
    func requestAuthorization(provisional: Bool) async -> ReminderAuthStatus
}

/// Seam 2 — scheduling. Identifier-scoped per `ReminderKind` (proposal §3.2):
/// scheduling a kind replaces that kind's pending request; it never accumulates.
public protocol ReminderScheduler: Sendable {

    /// Schedule (or replace) the reminder for `kind`. The Live impl removes the
    /// pending request with this kind's identifier first, then adds the new one —
    /// never `removeAll` (the 64-limit / async-race discipline, §3.2).
    func schedule(kind: ReminderKind, content: ReminderContent, on schedule: ReminderSchedule) async

    /// Cancel the pending request for one `kind`.
    func cancel(kind: ReminderKind) async

    /// Whether a pending request currently exists for `kind` — the
    /// scheduler-side ground truth (#817: used to seed the persisted
    /// `isScheduled` flag once for installs that predate it, instead of
    /// guessing a default).
    func hasPending(kind: ReminderKind) async -> Bool

    /// Cancel all of our reminder kinds (teardown / master opt-out, §3.4). Scoped
    /// to our known kind identifiers — not a system-wide `removeAll`.
    func cancelAll() async
}
