// ReminderPrimerCoordinator — Sudoku U1 daily-ready primer flow (#287 Phase 2).
//
// The value-moment glue between the shared GameShellUI primer chrome and the
// RemindersKit seams (proposal §5.1; design flow S02→S05). Owns:
//   - the localized Sudoku copy (ReminderPrimerCopy / ReminderDeniedCopy)
//   - the `ReminderPermissionModel` (GameShellUI) driving the system prompt
//   - the persisted fire time (#321 seam) + the `ReminderScheduler`
//   - the telemetry emit closure (primer shown/accepted/declined, scheduled)
//
// It depends ONLY on the `Reminders` protocol seams + GameShellUI; it never
// imports `UserNotifications` (that stays in AppComposition's Live layer). The
// host (LiveRouteFactory) constructs one per Daily-completion mount.
//
// `@MainActor @Observable` because it drives a `.sheet` on CompletionView and
// re-exposes `permissionModel.status` / `.isRequesting` for the sheet bindings.

public import SwiftUI
public import GameShellUI
public import Reminders
public import Telemetry

@MainActor
@Observable
public final class ReminderPrimerCoordinator {

    /// Drives the `ReminderPrimerSheet` presentation. The affordance on
    /// CompletionView flips this to `true`; accept/decline flip it back.
    public var isPrimerPresented = false

    /// Re-exposed for the sheet's spinner binding.
    public var isRequesting: Bool { permissionModel.isRequesting }

    /// Re-exposed so a host can branch on a `.denied` user (S06 explainer).
    public var status: ReminderAuthStatus { permissionModel.status }

    /// The shared primer copy (host-localized) handed to `ReminderPrimerSheet`.
    public let primerCopy: ReminderPrimerCopy

    /// The shared denial-explainer copy (S06). Exposed for hosts that surface
    /// the explainer; CompletionView wires only the primer in this pass.
    public let deniedCopy: ReminderDeniedCopy

    @ObservationIgnored private let permissionModel: ReminderPermissionModel
    @ObservationIgnored private let scheduler: any ReminderScheduler
    @ObservationIgnored private let settingsStore: ReminderSettingsStore
    /// Localized daily-ready notification payload (title/body). Injected so the
    /// shared scheduler stays content-neutral (proposal §3.3).
    @ObservationIgnored private let content: ReminderContent
    /// Decoupled telemetry emit — the host bridges this to `Telemetry.observe`.
    /// Avoids the coordinator holding the `Telemetry` actor (keeps it sync-testable).
    @ObservationIgnored private let emit: @Sendable (TelemetryEvent) -> Void

    public init(
        permissionModel: ReminderPermissionModel,
        scheduler: any ReminderScheduler,
        settingsStore: ReminderSettingsStore,
        content: ReminderContent,
        primerCopy: ReminderPrimerCopy,
        deniedCopy: ReminderDeniedCopy,
        emit: @escaping @Sendable (TelemetryEvent) -> Void = { _ in }
    ) {
        self.permissionModel = permissionModel
        self.scheduler = scheduler
        self.settingsStore = settingsStore
        self.content = content
        self.primerCopy = primerCopy
        self.deniedCopy = deniedCopy
        self.emit = emit
    }

    /// Present the soft primer at the value moment (flow S02→S03). Refreshes the
    /// system status first (the user may have toggled it in Settings) and emits
    /// `reminderPrimerShown`.
    public func presentPrimer() async {
        await permissionModel.refreshStatus()
        emit(.reminderPrimerShown(kind: ReminderKind.dailyReady.rawValue))
        isPrimerPresented = true
    }

    /// User accepted the primer (S03→S04). Fires the one-shot system prompt; on
    /// `.authorized` / `.provisional`, schedules the repeating daily reminder at
    /// the persisted fire time (S04→S05). Identifier-scoped — re-accepting
    /// replaces, never duplicates (proposal §3.2).
    public func acceptPrimer() async {
        emit(.reminderPrimerAccepted(kind: ReminderKind.dailyReady.rawValue))
        let resolved = await permissionModel.requestFromPrimer()
        isPrimerPresented = false
        guard resolved == .authorized || resolved == .provisional else { return }
        await scheduleDailyReady()
    }

    /// User tapped "Not now" (S03 self-return). Repeatable; fires no system
    /// prompt. Emits `reminderPrimerDeclined`.
    public func declinePrimer() {
        emit(.reminderPrimerDeclined(kind: ReminderKind.dailyReady.rawValue))
        isPrimerPresented = false
    }

    /// Schedule (or replace) the daily-ready reminder at the persisted fire time.
    /// Public so a foreground-reconcile path (S07: user flips Allow in Settings)
    /// can re-schedule without going through the primer.
    public func scheduleDailyReady() async {
        let time = settingsStore.dailyReadyFireTime
        await scheduler.schedule(
            kind: .dailyReady,
            content: content,
            on: .dailyAt(hour: time.hour, minute: time.minute)
        )
        emit(.reminderScheduled(kind: ReminderKind.dailyReady.rawValue))
    }
}
