// LiveNotificationAuthorizer — the production `NotificationAuthorizing`, wrapping
// `UNUserNotificationCenter.current()`.
//
// RESTRICTED IMPORT: this is one of the only two files in the package allowed to
// import `UserNotifications` (the other is LiveReminderScheduler). The seam keeps
// every UI / logic / test layer free of the framework — same discipline as
// CloudKit→Persistence, GoogleMobileAds→AdsAdMob (proposal §4.5).

internal import UserNotifications
internal import os

/// Maps `UNAuthorizationStatus` → our `ReminderAuthStatus`.
private func mapStatus(_ status: UNAuthorizationStatus) -> ReminderAuthStatus {
    switch status {
    case .notDetermined: .notDetermined
    case .denied: .denied
    case .authorized: .authorized
    case .provisional: .provisional
    case .ephemeral: .authorized   // App Clip ephemeral grant — treat as authorized
    @unknown default: .notDetermined
    }
}

public struct LiveNotificationAuthorizer: NotificationAuthorizing {

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

    public func currentStatus() async -> ReminderAuthStatus {
        let settings = await center.notificationSettings()
        return mapStatus(settings.authorizationStatus)
    }

    @discardableResult
    public func requestAuthorization(provisional: Bool) async -> ReminderAuthStatus {
        var options: UNAuthorizationOptions = [.alert, .sound]
        if provisional { options.insert(.provisional) }
        do {
            _ = try await center.requestAuthorization(options: options)
        } catch {
            // A thrown error here means the request itself failed (rare); the
            // resolved status below is still the source of truth.
            logger.error("requestAuthorization failed: \(error.localizedDescription, privacy: .public)")
        }
        return await currentStatus()
    }
}
