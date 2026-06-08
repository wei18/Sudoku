#if canImport(AppTrackingTransparency)
internal import AppTrackingTransparency
#endif

// MARK: - ATTPresenter
//
// Thin async wrapper over `ATTrackingManager.requestTrackingAuthorization`.
// Lives in AdsAdMob (not MonetizationCore) because only the ads layer needs to
// gate behavior on ATT outcome — IAP is exempt from tracking-prompt rules.
//
// Bridge seam: `ATTBridge` matches the `AdMobBridge` pattern. The production
// path uses `LiveATTBridge` which calls the real `ATTrackingManager`; tests
// inject `FakeATTBridge` to drive the four authorization states without UI.

public enum ATTOutcome: Sendable, Equatable {
    /// User has not been asked yet — request can be presented.
    case notDetermined
    /// User has authorized tracking. AdMob may use IDFA.
    case authorized
    /// User has denied tracking. AdMob will use non-personalized ads.
    case denied
    /// Tracking restricted by device policy (parental controls, MDM, etc.).
    case restricted
    /// Platform does not support ATT (macOS direct builds, etc.).
    case unsupported
}

internal protocol ATTBridge: Sendable {
    /// Current ATT status without prompting.
    func currentStatus() async -> ATTOutcome
    /// Present the ATT prompt if status is `.notDetermined`; return the
    /// updated outcome after user choice. No-op on other statuses.
    func requestAuthorization() async -> ATTOutcome
}

public enum ATTPresenter {
    /// Current ATT status WITHOUT prompting. Used by the pre-prompt flow
    /// (#371 / #195) to decide whether to offer the priming sheet at all — we
    /// only offer while the system has not yet asked (`.notDetermined`).
    public static func currentStatus() async -> ATTOutcome {
        await currentStatus(using: LiveATTBridge())
    }

    internal static func currentStatus(using bridge: any ATTBridge) async -> ATTOutcome {
        await bridge.currentStatus()
    }

    /// Request ATT only when the system has not yet asked; on every other
    /// status echo the current outcome. Idempotent across repeated calls.
    public static func requestIfNeeded() async -> ATTOutcome {
        await requestIfNeeded(using: LiveATTBridge())
    }

    /// Test injection point. Lives at the same access level as the live API
    /// so tests can drive the flow with `FakeATTBridge` without exposing the
    /// bridge protocol publicly.
    internal static func requestIfNeeded(using bridge: any ATTBridge) async -> ATTOutcome {
        let current = await bridge.currentStatus()
        if current == .notDetermined {
            return await bridge.requestAuthorization()
        }
        return current
    }
}

// MARK: - LiveATTBridge

internal struct LiveATTBridge: ATTBridge {
    internal func currentStatus() async -> ATTOutcome {
        #if canImport(AppTrackingTransparency)
        return Self.map(ATTrackingManager.trackingAuthorizationStatus)
        #else
        return .unsupported
        #endif
    }

    internal func requestAuthorization() async -> ATTOutcome {
        #if canImport(AppTrackingTransparency)
        let status = await ATTrackingManager.requestTrackingAuthorization()
        return Self.map(status)
        #else
        return .unsupported
        #endif
    }

    #if canImport(AppTrackingTransparency)
    /// Maps Apple's enum onto our `ATTOutcome`. `@unknown default` guards
    /// against Apple adding a new case in a future iOS release.
    private static func map(_ status: ATTrackingManager.AuthorizationStatus) -> ATTOutcome {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }
    #endif
}
