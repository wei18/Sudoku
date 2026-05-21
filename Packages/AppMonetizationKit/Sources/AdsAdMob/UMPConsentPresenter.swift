#if canImport(UserMessagingPlatform)
internal import UserMessagingPlatform
#endif

// MARK: - UMPConsentPresenter
//
// Google's User Messaging Platform (UMP) SDK ships as a sibling SPM product
// alongside `GoogleMobileAds`. We import `UserMessagingPlatform` directly
// here — NOT `GoogleMobileAds` — so the `rg "import GoogleMobileAds"` audit
// stays at one hit (LiveAdMobBridge.swift).
//
// Same bridge-seam pattern as `ATTPresenter`: the live path wraps UMP's
// global singletons; tests inject `FakeUMPBridge` to drive each outcome
// without spinning up the SDK or a UIViewController host.

public enum UMPConsentOutcome: Sendable, Equatable {
    /// Consent info refreshed and no consent form is required (e.g. user is
    /// outside GDPR/UMP-applicable region, or already consented).
    case notRequired
    /// User completed the consent form (granted or denied — UMP exposes the
    /// detail via `consentStatus`; for v2.2 we treat any post-form state as
    /// `.obtained` and let downstream code re-query the SDK for granular
    /// purposes).
    case obtained
    /// Consent flow failed — network error, form load failure, etc.
    case failed(reason: String)
    /// Platform does not support UMP (macOS direct builds, etc.).
    case unsupported
}

internal protocol UMPBridge: Sendable {
    /// Refresh consent info from UMP servers. Throws on network / config
    /// errors.
    func requestConsentInfoUpdate() async throws
    /// Whether a consent form is currently required (`consentStatus == .required`).
    func isConsentFormRequired() async -> Bool
    /// Load + present the consent form on the key window's root VC. Throws
    /// on load / presentation failures.
    func loadAndPresentConsentFormIfRequired() async throws
}

public enum UMPConsentPresenter {
    /// Refresh consent info; if a form is required, present it and wait for
    /// completion. Idempotent — safe to call on every app launch.
    public static func requestIfNeeded() async -> UMPConsentOutcome {
        await requestIfNeeded(using: LiveUMPBridge())
    }

    internal static func requestIfNeeded(using bridge: any UMPBridge) async -> UMPConsentOutcome {
        do {
            try await bridge.requestConsentInfoUpdate()
        } catch {
            return .failed(reason: String(describing: error))
        }
        let required = await bridge.isConsentFormRequired()
        guard required else { return .notRequired }
        do {
            try await bridge.loadAndPresentConsentFormIfRequired()
            return .obtained
        } catch {
            return .failed(reason: String(describing: error))
        }
    }
}

// MARK: - LiveUMPBridge

internal struct LiveUMPBridge: UMPBridge {
    internal func requestConsentInfoUpdate() async throws {
        #if canImport(UserMessagingPlatform)
        let parameters = RequestParameters()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        #else
        throw UMPBridgeError.unsupportedPlatform
        #endif
    }

    internal func isConsentFormRequired() async -> Bool {
        #if canImport(UserMessagingPlatform)
        return ConsentInformation.shared.consentStatus == .required
        #else
        return false
        #endif
    }

    internal func loadAndPresentConsentFormIfRequired() async throws {
        #if canImport(UserMessagingPlatform)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ConsentForm.loadAndPresentIfRequired(from: nil) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        #else
        throw UMPBridgeError.unsupportedPlatform
        #endif
    }
}

internal enum UMPBridgeError: Error, Equatable {
    case unsupportedPlatform
}
