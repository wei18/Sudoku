// Value types for the reminder mechanism — all `Sendable`, all game-agnostic.
//
// These are the data the host injects into the protocol seams
// (`NotificationAuthorizing` / `ReminderScheduler`). App-specific copy lives in
// each app's `Localizable.xcstrings` and is passed in as `ReminderContent`; the
// shared target never hard-codes app text (proposal §3.3 / §4.1).

public import Foundation

/// The user-facing payload of a reminder. App copy is injected — the shared
/// target is content-neutral (proposal §3.3).
public struct ReminderContent: Sendable, Equatable {

    /// Notification title.
    public var title: String

    /// Notification body.
    public var body: String

    /// Whether to attach the default notification sound. `false` → silent.
    /// (Sound is only delivered if the user granted `.sound`; honoring that is a
    /// Phase-2 delegate/settings concern — this flag is the intent.)
    public var sound: Bool

    /// Optional `UNNotificationCategory` identifier for foreground-presentation
    /// routing (Phase 2 delegate). `nil` → no category.
    public var categoryId: String?

    public init(
        title: String,
        body: String,
        sound: Bool = true,
        categoryId: String? = nil
    ) {
        self.title = title
        self.body = body
        self.sound = sound
        self.categoryId = categoryId
    }
}

/// When a reminder should fire. Maps 1:1 to a `UNNotificationTrigger` in the
/// Live scheduler (proposal §3.1 / §4.4).
public enum ReminderSchedule: Sendable, Equatable {

    /// Repeating daily at a fixed local time → repeating
    /// `UNCalendarNotificationTrigger`. One of the 64 slots, fires daily, survives
    /// reboots (proposal §3.1).
    case dailyAt(hour: Int, minute: Int)

    /// One-shot after a delay → `UNTimeIntervalNotificationTrigger(repeats: false)`.
    case after(seconds: TimeInterval)

    /// One-shot at a specific date → one-shot
    /// `UNCalendarNotificationTrigger(repeats: false)`.
    case onDate(DateComponents)
}

/// The reminder type. `rawValue` doubles as the stable per-type notification
/// **identifier** used for identifier-scoped replacement (proposal §3.2) — each
/// kind owns exactly one pending request, so rescheduling replaces rather than
/// piles up.
public enum ReminderKind: String, Sendable, CaseIterable {

    /// "Today's puzzle is ready" — Sudoku Daily anchor use case (U1).
    case dailyReady

    /// "Keep your N-day streak alive" (U2).
    case streakKeeper

    /// "Haven't played in a while" win-back nudge (U3).
    case comeback
}

/// Authorization status mirror of `UNAuthorizationStatus` — kept in this target
/// so callers never import `UserNotifications` (proposal §4.5 restricted import).
public enum ReminderAuthStatus: Sendable, Equatable {

    /// User has not yet been asked.
    case notDetermined

    /// User explicitly declined (recoverable only via Settings deep-link).
    case denied

    /// Full authorization (banner + sound).
    case authorized

    /// Provisional — quiet delivery to Notification Center, no upfront prompt
    /// (proposal §5.2).
    case provisional
}
