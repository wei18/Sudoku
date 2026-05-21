internal import MonetizationCore

// MARK: - AdMobBridge
//
// foundations.md §9.1 isolation contract: the Google Mobile Ads SDK API surface
// is wrapped behind this protocol seam. Only `LiveAdMobBridge.swift` is allowed
// to `import GoogleMobileAds`; every other AdsAdMob source file (including the
// public `LiveAdMobAdProvider`) operates against `any AdMobBridge` instead.
//
// Why a protocol seam:
//   1. Unit tests can substitute `FakeAdMobBridge` — the real SDK requires an
//      iOS UI host and network access; neither is feasible in `swift test`.
//   2. SDK API churn (renamed classes, new init signatures) is isolated to one
//      file. The rest of the module sees only Sendable value types.
//   3. macOS builds can compile this protocol (and the actor that consumes it)
//      because no Apple-iOS-only type leaks into the protocol surface.

internal protocol AdMobBridge: Sendable {
    /// Boot the underlying SDK. Implementations must be idempotent — the
    /// `LiveAdMobAdProvider` actor also latches on first success, but the
    /// bridge itself should tolerate repeat calls (some SDKs charge fees / log
    /// warnings for double-init).
    func start() async throws

    /// Request a banner load. Returns an opaque handle once the SDK reports
    /// success; throws an `AdMobBridgeError` (or rethrown SDK error) on
    /// failure. The handle does not pin lifecycle — the bridge / SDK owns the
    /// underlying `GADBannerView`.
    func loadBanner() async throws -> AdBannerHandle

    /// Last cached banner status. Pull-based; callers use `loadBanner()` for
    /// fresh state and this getter for repeat reads without re-firing a load.
    func currentBannerStatus() async -> AdBannerStatus
}

// MARK: - AdMobBridgeError

/// Common bridge-level failure reasons. The live bridge maps SDK-specific
/// errors onto these cases (or rethrows the raw error inside `.sdk`); fake
/// bridges can construct any case directly for negative-path tests.
internal enum AdMobBridgeError: Error, Equatable {
    /// SDK reported initialization failure (network, mediation config, etc.).
    case initializationFailed(reason: String)
    /// SDK reported a banner-load failure. Reason mirrors `GADRequestError.localizedDescription`.
    case loadFailed(reason: String)
    /// Platform does not support the AdMob SDK (e.g. running on macOS where
    /// the iOS binary target is unavailable). Surfaces as a hard error so the
    /// provider can mark `bannerStatus = .failed(...)` rather than silently
    /// loading nothing.
    case unsupportedPlatform
}
