public import Foundation

// MARK: - AdProvider
//
// Provider-neutral surface for "show a banner ad". Concrete implementation
// (AdsAdMob.LiveAdMobAdProvider) lives in a separate target so the third-party
// SDK dependency does not leak across MonetizationCore. See docs/v1/design.md §How.2.

public protocol AdProvider: Sendable {
    /// Start the underlying SDK and load the first banner. Idempotent — safe
    /// to call repeatedly; subsequent calls after the first are no-ops.
    func initialize() async throws

    /// Current ready-to-display banner state. Pull-based; the UI layer queries
    /// this when rendering a `BannerSlotView`.
    var bannerStatus: AdBannerStatus { get async }

    /// Force a fresh banner load. Used after the user dismisses the current
    /// banner and the gate re-opens (e.g. next calendar day).
    func refreshBanner() async throws

    /// Release the resources backing a previously loaded banner handle. The UI
    /// layer calls this when the `BannerSlotView` disappears so the live
    /// provider can drop its retained `GADBannerView` instead of holding it for
    /// the handle's lifetime (#221). No-op for providers that hold no per-handle
    /// state, and safe to call with an unknown / already-disposed handle.
    func dispose(handle: AdBannerHandle) async
}

// MARK: - AdBannerStatus

public enum AdBannerStatus: Sendable, Equatable {
    case notInitialized
    case loading
    case loaded(AdBannerHandle)
    case failed(reason: String)
    /// Suppressed because: user purchased Remove Ads, OR app is within 7-day
    /// grace period, OR user dismissed today. The provider does not decide
    /// suppression itself — `AdGate` does — but the provider reports the
    /// status downstream.
    case suppressed
}

// MARK: - AdBannerHandle

/// Opaque handle to a loaded banner. The concrete `LiveAdMobAdProvider` maps
/// this handle to its internal `GADBannerView` instance via a private lookup
/// table; the public surface never exposes the AdMob type.
public struct AdBannerHandle: Sendable, Equatable {
    public let id: UUID

    public init(id: UUID = UUID()) {
        self.id = id
    }
}
