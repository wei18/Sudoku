public import MonetizationCore
public import MonetizationUI
public import SwiftUI

// MARK: - LiveAdMobAdProvider
//
// The public `AdProvider` implementation backed by Google Mobile Ads. All SDK
// interactions go through `AdMobBridge` — this actor never imports
// `GoogleMobileAds` directly (foundations.md §9.1).
//
// Idempotency: `initialize()` latches via `didStart`. Repeat calls after first
// success are no-ops; calls after first failure re-attempt (the contract on
// `AdProvider.initialize()` says "safe to call repeatedly", which we read as
// "stable when successful, retryable on failure").

public actor LiveAdMobAdProvider: AdProvider {
    // `nonisolated` because the bridge is set once at init and never mutated;
    // the `@MainActor` `BannerViewProviding` conformance (below) reads it
    // without hopping onto the actor. `any AdMobBridge` is `Sendable`, so this
    // is safe.
    private nonisolated let bridge: any AdMobBridge
    private var didStart: Bool = false
    private var lastKnownStatus: AdBannerStatus = .notInitialized

    /// Production init. Wires `LiveAdMobBridge` — the only path that touches
    /// the Google Mobile Ads SDK.
    ///
    /// - Parameter bannerAdUnitID: AdMob banner unit ID. Per-app — chosen by
    ///   `SudokuAppComposition.Live` so the package can host multiple apps in the
    ///   same workspace without baking Sudoku-specific IDs into the binary.
    public init(bannerAdUnitID: String) {
        self.bridge = LiveAdMobBridge(bannerAdUnitID: bannerAdUnitID)
    }

    /// Test-only init. Inject a `FakeAdMobBridge` (in `AdsAdMobTests`) to drive
    /// the provider through deterministic scripted behavior without booting
    /// the real SDK.
    internal init(bridge: any AdMobBridge) {
        self.bridge = bridge
    }

    // MARK: AdProvider

    public var bannerStatus: AdBannerStatus {
        get async { lastKnownStatus }
    }

    public func initialize() async throws {
        if didStart { return }
        do {
            try await bridge.start()
            didStart = true
            lastKnownStatus = .loading
        } catch {
            // Surface as a `.failed` status so callers / UI can react, but
            // also rethrow so the caller can decide whether to retry.
            lastKnownStatus = .failed(reason: String(describing: error))
            throw error
        }
    }

    public func refreshBanner() async throws {
        guard didStart else {
            // `initialize()` is the documented precondition; calling refresh
            // first is a programmer error in the contract, but degrade
            // gracefully by surfacing a structured status rather than
            // crashing.
            lastKnownStatus = .failed(reason: "refreshBanner called before initialize")
            throw AdMobBridgeError.initializationFailed(reason: "not started")
        }
        lastKnownStatus = .loading
        do {
            let handle = try await bridge.loadBanner()
            lastKnownStatus = .loaded(handle)
        } catch {
            lastKnownStatus = .failed(reason: String(describing: error))
            throw error
        }
    }

    public func dispose(handle: AdBannerHandle) async {
        // Forward to the bridge for the real `GADBannerView` teardown (#221).
        // If the disposed handle is the one currently surfaced as `.loaded`,
        // drop the status to `.disposed` so a stale handle isn't reported after
        // its view is gone — and so the status stays honest that the SDK is
        // still initialized (not `.notInitialized`), only this handle released
        // (#276).
        await bridge.dispose(handle: handle)
        if case .loaded(handle) = lastKnownStatus {
            lastKnownStatus = .disposed
        }
    }
}

// MARK: - BannerViewProviding (#441)
//
// Lets the shared `MonetizationUI.BannerSlotView` render the real banner for a
// loaded handle. The view comes from the bridge as a type-erased `AnyView`, so
// `GoogleMobileAds` stays confined to `LiveAdMobBridge` (foundations.md §9.1).
extension LiveAdMobAdProvider: BannerViewProviding {
    @MainActor
    public func bannerView(for handle: AdBannerHandle) -> AnyView? {
        bridge.bannerView(for: handle)
    }
}
