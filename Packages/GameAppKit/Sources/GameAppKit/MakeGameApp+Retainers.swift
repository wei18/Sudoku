// MakeGameApp+Retainers — process-wide retainers used by `makeGameApp` (#556).
//
// Split out of `MakeGameApp.swift` to keep that file under the 400-line gate.
// These are the two "Apple holds a weak reference, so the host must retain it"
// singletons (MetricKit sink + UNUserNotificationCenter delegate) plus the
// delegate class itself. `UserNotifications` stays confined to this file (same
// discipline as RemindersKit's Live files — kept out of UI / logic / test).

internal import Foundation
internal import Telemetry
#if canImport(MetricKit)
internal import MetricKit
#endif
internal import UserNotifications

// MARK: - LiveMetricKitRetainer

/// Process-wide retainer for `MetricKitSink` — MXMetricManager's subscriber
/// list holds a weak reference, so we must keep the sink alive ourselves
/// for the lifetime of the App. Installation is idempotent.
enum LiveMetricKitRetainer {
    nonisolated(unsafe) private static var sink: MetricKitSink?
    private static let lock = NSLock()

    static func install(downstream: Telemetry) {
        lock.lock()
        defer { lock.unlock() }
        guard sink == nil else { return }
        let metricSink = MetricKitSink(downstream: downstream)
        // Skip system registration in test environments — MXMetricManager
        // is unavailable outside a properly entitled app bundle.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            metricSink.startReceivingSystemReports()
        }
        sink = metricSink
    }
}

// MARK: - GameReminderDelegateRetainer

/// Process-wide retainer for the game's `UNUserNotificationCenterDelegate`.
/// `UNUserNotificationCenter` holds its `delegate` weakly, so the host must
/// keep it alive for the app's lifetime. Idempotent.
enum GameReminderDelegateRetainer {
    @MainActor private static var delegate: GameReminderNotificationDelegate?

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
        let instance = GameReminderNotificationDelegate(onTap: onTap, emit: emit)
        delegate = instance
        guard !isRunningInTestProcess else { return }
        UNUserNotificationCenter.current().delegate = instance
    }
}

// MARK: - GameReminderNotificationDelegate

/// Foreground presentation + tap routing for reminder notifications.
/// Restricted import: `UserNotifications` is used only here (same discipline
/// as RemindersKit's Live files — kept out of UI / logic / test layers).
@MainActor
private final class GameReminderNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let onTap: @MainActor (String) -> Void
    private let emit: @Sendable (TelemetryEvent) -> Void

    init(
        onTap: @escaping @MainActor (String) -> Void,
        emit: @escaping @Sendable (TelemetryEvent) -> Void
    ) {
        self.onTap = onTap
        self.emit = emit
        super.init()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let identifier = notification.request.identifier
        emit(.reminderFired(kind: identifier))
        completionHandler([.banner, .sound])
    }

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
