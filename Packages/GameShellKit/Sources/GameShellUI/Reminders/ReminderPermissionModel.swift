// ReminderPermissionModel — the @Observable driver for the permission-priming
// UI (#287 Phase 2, proposal §4.4 / §5).
//
// Lives in GameShellUI (not the leaf `Reminders` target) because it drives
// SwiftUI shell chrome — the soft pre-ask primer sheet + the denial explainer —
// and both apps share that chrome (Q2 resolved → GameShellUI, see impl-notes
// D1). It depends ONLY on the `NotificationAuthorizing` protocol seam; it never
// imports `UserNotifications` (restricted to RemindersKit's Live files).
//
// Flow this model encodes (proposal §5.1 / flow visual):
//   - cold launch: status stays `.notDetermined`, NO system prompt (S01).
//   - at a value moment the host presents the primer (S03). The model does NOT
//     auto-present — the host owns *when* (post-Daily), the model owns the
//     status + the actions.
//   - `requestFromPrimer()` fires the ONE-shot system prompt (S04) and resolves
//     the status. Declining the primer (`dismissPrimer()`) fires nothing and is
//     repeatable (no system prompt).
//   - `.denied` → host shows the explainer + `openSettings()` (S06).

public import SwiftUI
// `public` because the model's API surface (`status: ReminderAuthStatus`, the
// `NotificationAuthorizing` init param) re-exposes these `Reminders` types.
public import Reminders

#if canImport(UIKit)
internal import UIKit
#endif

/// `@MainActor @Observable` driver for the reminder permission flow. The host
/// constructs one with a `NotificationAuthorizing` seam; the primer sheet view
/// reads `status` and calls the actions.
@MainActor
@Observable
public final class ReminderPermissionModel {

    /// The latest known authorization status. Seeded `.notDetermined`; refreshed
    /// via `refreshStatus()` (call on foreground / before presenting the primer,
    /// proposal §5.1 step 6).
    public private(set) var status: ReminderAuthStatus = .notDetermined

    /// `true` while the system one-shot prompt is in flight — lets the primer CTA
    /// show a spinner and avoids a double-tap re-fire.
    public private(set) var isRequesting = false

    private let authorizer: any NotificationAuthorizing

    /// Whether to request provisional (quiet) authorization. `false` for U1
    /// Daily-ready (must be visible, proposal §5.2); the seam stays so U3 can
    /// flip it without an API change.
    private let provisional: Bool

    public init(
        authorizer: any NotificationAuthorizing,
        provisional: Bool = false,
        initialStatus: ReminderAuthStatus = .notDetermined
    ) {
        self.authorizer = authorizer
        self.provisional = provisional
        self.status = initialStatus
    }

    /// Re-read the system status (the user can change it in Settings at any
    /// time). Call before presenting the primer and on foreground.
    public func refreshStatus() async {
        status = await authorizer.currentStatus()
    }

    /// The user accepted the soft primer → fire the one-and-only system prompt
    /// (S03 → S04). Updates `status` to the resolved value. No-op if already in
    /// flight. Returns the resolved status so the caller can chain scheduling.
    @discardableResult
    public func requestFromPrimer() async -> ReminderAuthStatus {
        guard !isRequesting else { return status }
        isRequesting = true
        defer { isRequesting = false }
        status = await authorizer.requestAuthorization(provisional: provisional)
        return status
    }

    /// Deep-link to the system notification settings (iOS) so a `.denied` user
    /// can re-enable (S06 → S07). On macOS there is no AppKit deep-link
    /// (proposal P12) — the host shows textual guidance instead; this is a no-op.
    public func openSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
        // macOS: no openNotificationSettingsURLString (P12). The denial explainer
        // shows textual "System Settings → Notifications → [App]" guidance and
        // omits the button — handled at the view layer.
    }
}
