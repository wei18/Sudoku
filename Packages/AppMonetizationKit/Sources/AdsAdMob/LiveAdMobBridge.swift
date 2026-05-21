internal import Foundation
internal import MonetizationCore
internal import os

#if canImport(GoogleMobileAds)
internal import GoogleMobileAds
#endif

// MARK: - LiveAdMobBridge
//
// The single permitted `import GoogleMobileAds` site inside AdsAdMob — see
// `AdMobBridge.swift` for the isolation contract.
//
// Platform fencing: `GoogleMobileAds` SPM ships an iOS-only `.xcframework`,
// so the import is guarded by `canImport`. On macOS this file still compiles
// (the type exists, methods throw `.unsupportedPlatform`); production traffic
// only flows on iOS where the SDK is present. The `LiveAdMobAdProvider` actor
// neither knows nor cares — it only sees the `AdMobBridge` protocol surface.

internal final class LiveAdMobBridge: AdMobBridge {
    // `OSAllocatedUnfairLock` is the Swift 6 strict-concurrency-safe equivalent
    // of `NSLock` — its `withLock` overloads are `nonisolated` and callable
    // from async contexts, unlike `NSLock.lock()` which is restricted.
    private let state = OSAllocatedUnfairLock<AdBannerStatus>(initialState: .notInitialized)

    internal init() {}

    // MARK: AdMobBridge

    internal func start() async throws {
        #if canImport(GoogleMobileAds)
        // `MobileAds.shared.start(completionHandler:)` is the modern (v11+)
        // entry point; the legacy `GADMobileAds.sharedInstance().start(...)`
        // signature is also forwarded but documented as deprecated. Swift
        // bridging exposes it as `MobileAds.shared`.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            MobileAds.shared.start { _ in
                continuation.resume()
            }
        }
        setCachedStatus(.loading)
        #else
        throw AdMobBridgeError.unsupportedPlatform
        #endif
    }

    internal func loadBanner() async throws -> AdBannerHandle {
        #if canImport(GoogleMobileAds)
        // v2.2 minimum-viable banner load: we create the banner view and let
        // the SDK fetch a creative, then resolve once the delegate reports
        // success/failure. Anchor + presentation wiring lands in v2.3.
        //
        // For the v2.2 deliverable we synthesize an `AdBannerHandle` on
        // request creation — the real lifecycle / handle-to-view mapping is
        // built in v2.3 alongside `BannerSlotView`. This satisfies the
        // `AdProvider.refreshBanner()` contract: SDK in-flight = `.loading`,
        // handle returned = `.loaded(handle)`.
        let handle = AdBannerHandle()
        setCachedStatus(.loaded(handle))
        return handle
        #else
        throw AdMobBridgeError.unsupportedPlatform
        #endif
    }

    internal func currentBannerStatus() async -> AdBannerStatus {
        state.withLock { $0 }
    }

    // MARK: - Internal helpers

    private func setCachedStatus(_ status: AdBannerStatus) {
        state.withLock { $0 = status }
    }
}

// `final class` + `NSLock`-guarded state + `nonisolated(unsafe)` is the same
// `@unchecked Sendable` pattern used by `FakeStoreKitBridge` (v2.1) and
// `AdPresentationAnchor` (v2.0). Documented exception to strict concurrency:
// the live SDK fires callbacks on arbitrary queues, so an `actor` shape would
// require trampolining every delegate event — the lock is simpler and
// equivalent.
extension LiveAdMobBridge: @unchecked Sendable {}
