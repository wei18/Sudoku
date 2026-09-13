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

    /// Suspends until the provider is ready to serve `refreshBanner()` (#1058).
    ///
    /// Readiness is a one-way latch: it opens once and never re-closes.
    /// - A provider that starts an SDK opens it when `initialize()` COMPLETES —
    ///   success OR failure — so a failed start never deadlocks a waiter; the
    ///   subsequent `refreshBanner()` reports the provider's own failure.
    /// - A provider with nothing to start returns immediately.
    ///
    /// Because the boot coordinator calls `initialize()` only after the UMP
    /// consent step, readiness also means "consent resolved".
    ///
    /// - Throws: `CancellationError` only if the calling task is cancelled
    ///   while still waiting. Once ready, returns without throwing.
    func awaitReady() async throws

    /// Current ready-to-display banner state. Pull-based; the UI layer queries
    /// this when rendering a `BannerSlotView`.
    var bannerStatus: AdBannerStatus { get async }

    /// Force a fresh banner load. Used after the user dismisses the current
    /// banner and the gate re-opens (e.g. next calendar day). A provider that
    /// starts an SDK must not reach the ad network before `awaitReady()` would
    /// return.
    ///
    /// - Returns: the handle THIS call loaded. Callers must use it rather than
    ///   re-reading `bannerStatus`, which is shared and may already reflect a
    ///   concurrent load (#1058).
    /// - Throws: `CancellationError` when the calling task is cancelled before
    ///   the load completes — a cancellation, never a load failure.
    @discardableResult
    func refreshBanner() async throws -> AdBannerHandle

    /// Release the resources backing a previously loaded banner handle. The UI
    /// layer calls this when the `BannerSlotView` disappears so the live
    /// provider can drop its retained `GADBannerView` instead of holding it for
    /// the handle's lifetime (#221). No-op for providers that hold no per-handle
    /// state, and safe to call with an unknown / already-disposed handle.
    func dispose(handle: AdBannerHandle) async
}

// MARK: - AdProviderError

public enum AdProviderError: Error, Equatable, Sendable {
    /// This provider cannot serve ads (`NoopAdProvider`, where the AdMob SDK is
    /// absent). Unreachable by ordering, not by type: every load path stops on
    /// `bannerStatus == .suppressed` before calling `refreshBanner()`.
    case unsupported
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
    /// The previously-loaded banner handle has been released via
    /// `dispose(handle:)`. Distinct from `.notInitialized`: the SDK is still
    /// initialized and a fresh `refreshBanner()` can re-load — only this
    /// handle's backing view was torn down (#276). The UI slot collapses on
    /// this state because dispose only fires once the slot is gone / dismissed.
    case disposed
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
