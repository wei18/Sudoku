// ReminderNotificationDelegate — foreground presentation + tap routing for
// reminder notifications (#287 Phase 2, flow S05/S07–S09).
//
// RESTRICTED IMPORT: this is the host-layer bridge to `UserNotifications`. Per
// the proposal §4.5 discipline the framework stays out of UI / logic / RemindersKit
// non-Live layers; the delegate has to import it (it conforms to
// `UNUserNotificationCenterDelegate`), so it lives here in AppComposition next to
// the other Live wiring — never in SudokuUI or GameShellUI.
//
// Two responsibilities:
//   1. willPresent — a reminder arrives while the app is foregrounded. Present
//      it as a banner+sound (default iOS would suppress it) and emit
//      `reminderFired` (flow S05).
//   2. didReceive — the user TAPPED a delivered reminder. Emit `reminderOpenedApp`
//      and deep-link to the route the reminder maps to (dailyReady → Daily hub,
//      flow S07→S09).

internal import Foundation
internal import Telemetry
internal import UserNotifications

/// Routes a fired/tapped reminder by its `ReminderKind.rawValue` identifier.
/// `@MainActor` because the tap route mutates `RootViewModel.path` (SwiftUI nav).
@MainActor
final class ReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {

    /// Deep-link a tapped reminder. Param is the notification identifier, which
    /// equals `ReminderKind.rawValue` (LiveReminderScheduler uses kind.rawValue
    /// as the request identifier). The host maps it to a navigation push.
    private let onTap: @MainActor (String) -> Void

    /// Telemetry emit — bridged to the `Telemetry` actor by the host.
    private let emit: @Sendable (TelemetryEvent) -> Void

    init(
        onTap: @escaping @MainActor (String) -> Void,
        emit: @escaping @Sendable (TelemetryEvent) -> Void
    ) {
        self.onTap = onTap
        self.emit = emit
        super.init()
    }

    // Foreground delivery (flow S05). Default behaviour is to NOT show a banner
    // while the app is active; we opt in so the daily-ready nudge is visible.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let identifier = notification.request.identifier
        emit(.reminderFired(kind: identifier))
        completionHandler([.banner, .sound])
    }

    // Tap routing (flow S07→S09). Emit, hop to the main actor to deep-link,
    // then tell the system we're done. The completion handler is invoked
    // synchronously here (the routing itself is fire-and-forget on the main
    // actor) to avoid capturing the task-isolated handler into a @MainActor
    // closure (which the compiler flags as a sending data race).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        emit(.reminderOpenedApp(kind: identifier))
        let route = onTap
        Task { @MainActor in route(identifier) }
        completionHandler()
    }
}

/// Process-wide retainer for the notification-center delegate — `UNUserNotificationCenter`
/// holds its `delegate` weakly, so the host must keep it alive for the app's
/// lifetime. Idempotent (mirrors `LiveMetricKitRetainer`). Skips system
/// registration under tests: `UNUserNotificationCenter.current()` requires a
/// real, entitled app bundle and crashes in the SwiftPM test runner (whose main
/// bundle is the toolchain, with no bundle identifier).
enum ReminderDelegateRetainer {
    @MainActor private static var delegate: ReminderNotificationDelegate?

    /// `true` in a unit-test process. Covers both XCTest (which sets
    /// `XCTestConfigurationFilePath`) and swift-testing (which does not — there
    /// we fall back to "no real app bundle identifier", true in the SwiftPM
    /// test runner). The live app always has a bundle id, so registration runs.
    private static var isRunningInTestProcess: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return true
        }
        return Bundle.main.bundleIdentifier == nil
    }

    @MainActor
    static func install(
        onTap: @escaping @MainActor (String) -> Void,
        emit: @escaping @Sendable (TelemetryEvent) -> Void
    ) {
        guard delegate == nil else { return }
        let instance = ReminderNotificationDelegate(onTap: onTap, emit: emit)
        delegate = instance
        guard !isRunningInTestProcess else { return }
        UNUserNotificationCenter.current().delegate = instance
    }
}
