// ReminderTimeSettingsModel — the #321 Settings fire-time control.
//
// Owns the persisted daily-ready fire time (`ReminderSettingsStore`, the #287
// seam) and reschedules the repeating `dailyReady` reminder when the user picks
// a new time. The Settings row binds a `DatePicker` to `fireDate`; on change the
// model persists the hour/minute and re-schedules `.dailyAt(hour, minute)`.
//
// Lifetime: unlike `ReminderPrimerCoordinator` (built fresh per Daily-completion
// mount), this model is built per Settings mount. Both read/write the SAME
// `ReminderSettingsStore` keys, so a change here is visible to the next primer
// schedule and vice-versa.
//
// Permission discipline (proposal §5.1 / matching the coordinator's accept
// path): the picker ALWAYS persists the chosen time, but only reschedules when
// the system status is `.authorized` / `.provisional`. A `.denied` /
// `.notDetermined` user has no pending request to replace — scheduling would be
// dropped by iOS anyway — so we skip the no-op center call and keep the persisted
// value ready for when they later grant via the primer or Settings deep-link.
//
// It depends ONLY on the `Reminders` protocol seams + the persisted store; it
// never imports `UserNotifications`.

public import SwiftUI
public import Reminders
public import Telemetry

@MainActor
@Observable
public final class ReminderTimeSettingsModel {

    /// The picked fire time, surfaced to the `DatePicker` as a `Date` (today's
    /// date at the persisted hour/minute — the picker shows only hour+minute).
    /// Seeded from the persisted value so the row opens on the user's choice.
    /// `didSet` fires on every picker change (NOT during `init`, where the
    /// stored property is set directly), so the seed never triggers a reschedule.
    public var fireDate: Date {
        didSet { persistAndReschedule() }
    }

    @ObservationIgnored private let settingsStore: ReminderSettingsStore
    @ObservationIgnored private let scheduler: any ReminderScheduler
    @ObservationIgnored private let authorizer: any NotificationAuthorizing
    /// Localized daily-ready payload — injected so the shared scheduler stays
    /// content-neutral (proposal §3.3). Mirrors the coordinator's `content`.
    @ObservationIgnored private let content: ReminderContent
    @ObservationIgnored private let emit: @Sendable (TelemetryEvent) -> Void
    @ObservationIgnored private let calendar: Calendar
    /// Serializes rapid picker changes: a new pick cancels the in-flight
    /// reschedule so the last-picked time is the one that lands (CR #321 Med).
    @ObservationIgnored private var rescheduleTask: Task<Void, Never>?

    public init(
        settingsStore: ReminderSettingsStore,
        scheduler: any ReminderScheduler,
        authorizer: any NotificationAuthorizing,
        content: ReminderContent,
        emit: @escaping @Sendable (TelemetryEvent) -> Void = { _ in },
        calendar: Calendar = .current
    ) {
        self.settingsStore = settingsStore
        self.scheduler = scheduler
        self.authorizer = authorizer
        self.content = content
        self.emit = emit
        self.calendar = calendar
        let time = settingsStore.dailyReadyFireTime
        self.fireDate = Self.date(hour: time.hour, minute: time.minute, calendar: calendar)
    }

    /// Persist the picked hour/minute, then reschedule the daily reminder when
    /// the user has granted notifications. Driven by `fireDate.didSet`.
    private func persistAndReschedule() {
        let components = calendar.dateComponents([.hour, .minute], from: fireDate)
        let time = ReminderFireTime(
            hour: components.hour ?? 0,
            minute: components.minute ?? 0
        )
        settingsStore.dailyReadyFireTime = time
        rescheduleTask?.cancel()
        rescheduleTask = Task { await reschedule(time) }
    }

    /// Reschedule `dailyReady` at `time` — but only if the system status permits
    /// a pending request to land. Identifier-scoped: replaces the kind's pending
    /// request, never accumulates (proposal §3.2).
    private func reschedule(_ time: ReminderFireTime) async {
        let status = await authorizer.currentStatus()
        guard status == .authorized || status == .provisional else { return }
        if Task.isCancelled { return } // superseded by a newer pick — don't land a stale time
        await scheduler.schedule(
            kind: .dailyReady,
            content: content,
            on: .dailyAt(hour: time.hour, minute: time.minute)
        )
        emit(.reminderScheduled(kind: ReminderKind.dailyReady.rawValue))
    }

    /// Build a `Date` carrying only the given hour/minute (anchored to today).
    /// The `DatePicker(.hourAndMinute)` displays only the time fields.
    private static func date(hour: Int, minute: Int, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? Date()
    }
}
