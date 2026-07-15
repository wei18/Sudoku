// ReminderSettingsModel — the shared Settings-screen reminder entry driver
// (#287: "the reminders entry must be wired into the Settings screen").
//
// The post-Daily `ReminderPrimerCoordinator` (SudokuKit) primes the permission at
// a value moment; this model primes it from a USER-INITIATED Settings entry, so a
// player who never solved a Daily — or who declined the post-Daily primer — can
// still turn reminders on. It is the single shared driver for BOTH apps'
// Settings reminder section (Minesweeper mirrors Sudoku): owning the enable /
// permission flow, the daily fire-time, and the reschedule-on-change wiring.
//
// Lives in GameShellUI (shared chrome, like `ReminderPermissionModel` / the
// primer sheet) so neither app re-implements it. It depends ONLY on the
// `Reminders` protocol seams + injected copy + injected persistence closures —
// it never imports `UserNotifications` (restricted to RemindersKit's Live files)
// and never couples to either app's concrete settings store.
//
// Persistence is injected as a `getFireTime` / `setFireTime` closure pair (a
// `(hour, minute)` tuple) rather than a concrete store type, so Sudoku can bridge
// to its existing `ReminderSettingsStore` (shared with the post-Daily coordinator)
// and Minesweeper can use its own `UserDefaults`-backed closures with its own key
// prefix — no shared store type, no cross-app key collision.
//
// `@MainActor @Observable` because it drives Settings rows + a `.sheet`
// (the primer) and re-exposes status/isRequesting/presentation flags for bindings.

public import SwiftUI
public import Reminders

@MainActor
@Observable
public final class ReminderSettingsModel {

    /// A telemetry-decoupled event the model emits when it schedules / cancels.
    /// The host bridges these to its `Telemetry` facade (GameShellUI does not
    /// depend on `Telemetry`, mirroring the post-Daily coordinator's `emit` seam).
    public enum Event: Sendable, Equatable {
        case scheduled(kind: String)
        case cancelled(kind: String)
        case primerAccepted(kind: String)
        case primerDeclined(kind: String)
    }

    /// Latest known system authorization status. Seeded `.notDetermined`;
    /// refreshed by `onAppear()` (the user may have toggled it in Settings.app).
    /// Drives which row the section shows: enable button vs. "On" + time picker
    /// vs. the denied deep-link.
    public private(set) var status: ReminderAuthStatus = .notDetermined

    /// Drives the primer `.sheet` presentation. `enable()` flips this true;
    /// accept/decline flip it back.
    public var isPrimerPresented = false

    /// Drives the denial-explainer `.sheet` presentation (a `.denied` user taps
    /// the status row → recovery deep-link).
    public var isDeniedExplainerPresented = false

    /// Re-exposed for the primer CTA spinner binding.
    public var isRequesting: Bool { permissionModel.isRequesting }

    /// Whether the managed reminder is currently scheduled — distinct from the
    /// OS `status`. A user can be `.authorized` yet have turned scheduling off
    /// in-app via `disable()`; the OS permission itself is never revoked by
    /// that action (only iOS/Settings.app can revoke it). This is what the
    /// section's row switch keys on to show the On rows vs. the enable row
    /// (#817: `disable()` used to leave this section with no observable state
    /// change at all — `status` never moved off `.authorized`, so the row the
    /// user was looking at didn't change and the tap looked dead).
    public private(set) var isScheduled: Bool

    /// The picked daily fire time, surfaced to the `DatePicker` as a `Date`
    /// (today's date at the persisted hour/minute — the picker shows only
    /// hour+minute). Seeded from the persisted value in `init`. `didSet` fires on
    /// every picker change (NOT during `init`, where the stored property is set
    /// directly), so the seed never triggers a reschedule.
    public var fireDate: Date {
        didSet { persistAndReschedule() }
    }

    @ObservationIgnored private let permissionModel: ReminderPermissionModel
    @ObservationIgnored private let scheduler: any ReminderScheduler
    /// The reminder kind this Settings entry manages (Sudoku → `.dailyReady`).
    @ObservationIgnored private let kind: ReminderKind
    /// Localized notification payload — injected so the shared scheduler stays
    /// content-neutral (proposal §3.3).
    @ObservationIgnored private let content: ReminderContent
    /// Persisted fire time read/write seam — injected so this model is store-agnostic.
    @ObservationIgnored private let getFireTime: () -> (hour: Int, minute: Int)
    @ObservationIgnored private let setFireTime: ((hour: Int, minute: Int)) -> Void
    /// Persisted `isScheduled` read/write seam, same DI shape as `getFireTime` /
    /// `setFireTime` — so the on/off flip survives relaunch instead of reverting
    /// to "On" the next time `onAppear()` re-reads the (still-authorized) OS
    /// status. Tri-state read: `nil` means no value was ever persisted (an
    /// install predating the flag), in which case `onAppear()` seeds it ONCE
    /// from scheduler ground truth (`hasPending(kind:)`) and persists the
    /// result — correct for every legacy population, including users whose
    /// pre-#817 `disable()` tap genuinely cancelled the notification but had
    /// nowhere to record it.
    @ObservationIgnored private let getIsScheduled: () -> Bool?
    @ObservationIgnored private let setIsScheduled: (Bool) -> Void
    /// Telemetry-decoupled emit — host bridges to `Telemetry.observe`.
    @ObservationIgnored private let emit: @Sendable (Event) -> Void
    @ObservationIgnored private let calendar: Calendar
    /// Serializes rapid picker changes: a new pick cancels the in-flight
    /// reschedule so the last-picked time is the one that lands.
    @ObservationIgnored private var rescheduleTask: Task<Void, Never>?

    public init(
        permissionModel: ReminderPermissionModel,
        scheduler: any ReminderScheduler,
        kind: ReminderKind,
        content: ReminderContent,
        getFireTime: @escaping () -> (hour: Int, minute: Int),
        setFireTime: @escaping ((hour: Int, minute: Int)) -> Void,
        getIsScheduled: @escaping () -> Bool? = { true },
        setIsScheduled: @escaping (Bool) -> Void = { _ in },
        emit: @escaping @Sendable (Event) -> Void = { _ in },
        calendar: Calendar = .current
    ) {
        self.permissionModel = permissionModel
        self.scheduler = scheduler
        self.kind = kind
        self.content = content
        self.getFireTime = getFireTime
        self.setFireTime = setFireTime
        self.getIsScheduled = getIsScheduled
        self.setIsScheduled = setIsScheduled
        self.emit = emit
        self.calendar = calendar
        let time = getFireTime()
        self.fireDate = Self.date(hour: time.hour, minute: time.minute, calendar: calendar)
        // No persisted value yet → assume scheduled until `onAppear()` seeds
        // from ground truth (keeps the pre-#817 render for the first frame).
        self.isScheduled = getIsScheduled() ?? true
    }

    /// Whether reminders are effectively on (a pending request can land).
    public var isEnabled: Bool {
        status == .authorized || status == .provisional
    }

    // MARK: - Lifecycle

    /// Refresh the system status when the Settings screen appears (the user may
    /// have changed it in Settings.app). Also re-seeds the picker from the
    /// persisted value in case the post-Daily primer changed nothing but another
    /// surface did.
    ///
    /// One-time migration (#817): when NO persisted `isScheduled` value exists
    /// (an install predating the flag), seed it from scheduler ground truth —
    /// does a pending request for our kind actually exist? — then persist.
    /// This covers users whose pre-#817 "Turn off reminders" tap genuinely
    /// cancelled the notification but had nowhere to record it: a blind `true`
    /// default would show them "On" while reality is off.
    public func onAppear() async {
        await permissionModel.refreshStatus()
        status = permissionModel.status
        if getIsScheduled() == nil {
            let pendingExists = await scheduler.hasPending(kind: kind)
            // #817 CR round-2: re-check after the await — a concurrent
            // disable()/scheduleDaily() during the suspension may have already
            // persisted the user's EXPLICIT intent; the one-shot ground-truth
            // seed must never clobber it (TOCTOU guard).
            guard getIsScheduled() == nil else { return }
            isScheduled = pendingExists
            setIsScheduled(pendingExists)
        }
    }

    // MARK: - Enable / permission flow

    /// User tapped the enable row while NOT yet authorized → present the soft
    /// pre-ask primer (the shared `ReminderPrimerSheet`). No system prompt fires
    /// until they accept inside the sheet.
    public func enable() {
        // Defensive: a double-tap before the sheet commits would otherwise
        // re-enter and re-present (CR #287). No-op if the primer is already up.
        guard !isPrimerPresented else { return }
        isPrimerPresented = true
    }

    /// User accepted the primer → fire the one-and-only system prompt; on
    /// `.authorized` / `.provisional`, schedule the daily reminder at the
    /// persisted time. Identifier-scoped — re-accepting replaces, never
    /// duplicates (proposal §3.2).
    public func acceptPrimer() async {
        emit(.primerAccepted(kind: kind.rawValue))
        let resolved = await permissionModel.requestFromPrimer()
        status = resolved
        isPrimerPresented = false
        guard resolved == .authorized || resolved == .provisional else { return }
        await scheduleDaily()
    }

    /// User tapped "Not now" in the primer — repeatable, fires no system prompt.
    public func declinePrimer() {
        emit(.primerDeclined(kind: kind.rawValue))
        isPrimerPresented = false
    }

    /// User tapped the status row while `.denied` → present the recovery
    /// explainer (deep-link to Settings on iOS; textual guidance on macOS).
    public func showDeniedExplainer() {
        isDeniedExplainerPresented = true
    }

    /// Deep-link to the system notification settings so a `.denied` user can
    /// re-enable (iOS only; no-op on macOS — the explainer shows guidance).
    public func openSystemSettings() {
        permissionModel.openSettings()
    }

    /// Dismiss the denial explainer.
    public func dismissDeniedExplainer() {
        isDeniedExplainerPresented = false
    }

    // MARK: - Scheduling

    /// Schedule (or replace) the managed reminder at the persisted fire time.
    public func scheduleDaily() async {
        let time = getFireTime()
        await scheduler.schedule(
            kind: kind,
            content: content,
            on: .dailyAt(hour: time.hour, minute: time.minute)
        )
        isScheduled = true
        setIsScheduled(true)
        emit(.scheduled(kind: kind.rawValue))
    }

    /// User turned reminders off from the section → cancel the pending request
    /// and flip `isScheduled` (persisted) so the section immediately swaps off
    /// the On rows (#817: previously only the scheduler-side cancel happened;
    /// no observable state changed, so the row on screen never moved and the
    /// tap looked like it did nothing). The system authorization itself is
    /// owned by iOS; this only removes our scheduled reminder so it stops
    /// firing — `status` stays `.authorized`/`.provisional`.
    public func disable() async {
        await scheduler.cancel(kind: kind)
        isScheduled = false
        setIsScheduled(false)
        emit(.cancelled(kind: kind.rawValue))
    }

    /// Persist the picked hour/minute, then reschedule when granted. Driven by
    /// `fireDate.didSet`.
    private func persistAndReschedule() {
        let components = calendar.dateComponents([.hour, .minute], from: fireDate)
        let time = (hour: components.hour ?? 0, minute: components.minute ?? 0)
        setFireTime(time)
        rescheduleTask?.cancel()
        rescheduleTask = Task { await reschedule(time) }
    }

    /// Reschedule at `time` — only if the status permits a pending request to
    /// land. Identifier-scoped: replaces the kind's pending request (proposal §3.2).
    private func reschedule(_ time: (hour: Int, minute: Int)) async {
        guard isEnabled, isScheduled else { return }
        if Task.isCancelled { return } // superseded by a newer pick
        await scheduler.schedule(
            kind: kind,
            content: content,
            on: .dailyAt(hour: time.hour, minute: time.minute)
        )
        emit(.scheduled(kind: kind.rawValue))
    }

    /// Build a `Date` carrying only the given hour/minute (anchored to today).
    private static func date(hour: Int, minute: Int, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? Date()
    }
}
