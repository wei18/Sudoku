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
        // AdMob 11.x ships only ObjC-prefixed symbols (`GADMobileAds`); the
        // Swift-friendly `MobileAds` name was introduced in 12.x. The package
        // is pinned to `from: "11.0.0"` per foundations.md §9.1, so we use the
        // ObjC type names directly. When the SDK pin is bumped to 12.x the
        // bridge seam (this file) is the single switch point.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            GADMobileAds.sharedInstance().start { _ in
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
        // Real SDK wiring (GADBannerView + Request + delegate) lands in v2.3.5
        // alongside `BannerSlotView`. Until then we surface a visible failure
        // so the UI layer cannot pretend a creative was fetched.
        let reason = "loadBanner not implemented until v2.3.5"
        setCachedStatus(.failed(reason: reason))
        throw AdMobBridgeError.loadFailed(reason: reason)
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
