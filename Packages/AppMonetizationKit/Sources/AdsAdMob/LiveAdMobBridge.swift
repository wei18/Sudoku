internal import Foundation
internal import MonetizationCore
internal import os

#if canImport(GoogleMobileAds)
internal import GoogleMobileAds
#endif

#if canImport(UIKit)
internal import UIKit
#endif

// MARK: - Ad unit IDs
//
// v2.5.2 ships with Google's universal TEST banner ad unit so real-device
// verification cannot serve production creatives. v2.5.3 (user-owned, just
// before ASC submission) swaps to the production ad unit ID. The
// `GADApplicationIdentifier` in `App/Info.plist` follows the same DEBUG vs
// production swap point — both flip together; see
// `docs/v2/v2.5-readiness.md §v2.5.3`.
//
// `#if DEBUG` over Info.plist read: keeps the ID local to the one file that
// already isolates Google SDK concerns (foundations.md §9.1), and matches the
// "single grep target for the swap" property the readiness doc relies on.

#if DEBUG
private let bannerAdUnitID = "ca-app-pub-3940256099942544/2934735716"  // Google test
#else
// v2.5.3 swap site: replace this with the production ad unit ID once
// `GADApplicationIdentifier` in `App/Info.plist` is also swapped to the
// production app ID. See `docs/v2/v2.5-readiness.md §v2.5.3` paired-flip
// checklist. The `fatalError` is intentional — any Release build that
// reaches this site before the v2.5.3 swap fails loudly at first ad load
// rather than silently serving an empty/test placeholder.
private var bannerAdUnitID: String {
    fatalError("REPLACE_IN_v2.5.3: production AdMob banner ad unit ID not wired — see docs/v2/v2.5-readiness.md §v2.5.3")
}
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

    #if canImport(GoogleMobileAds)
    // Live `BannerView` instances are retained here keyed by `AdBannerHandle.id`
    // so they survive past the delegate callback that resolves `loadBanner()`.
    // A later phase (out of v2.5.2 scope) plumbs the view into a SwiftUI
    // `UIViewRepresentable` via a UIKit-typed accessor that stays internal to
    // AdsAdMob (foundations §9.1: `GADBannerView` / `BannerView` must not cross
    // the target border).
    private let liveBanners = OSAllocatedUnfairLock<[UUID: BannerView]>(initialState: [:])

    // In-flight delegates are strong-held here because `BannerView.delegate` is
    // weak. The delegate removes itself on first callback (success OR failure).
    private let inFlightDelegates = OSAllocatedUnfairLock<Set<BannerLoadDelegate>>(initialState: [])
    #endif

    internal init() {}

    // MARK: AdMobBridge

    internal func start() async throws {
        #if canImport(GoogleMobileAds)
        // AdMob 13.x exposes Swift-native names via `NS_SWIFT_NAME` annotations:
        // `GADMobileAds` → `MobileAds`, `sharedInstance` → `shared`. The bridge
        // seam (this file) is the single switch point if Google bumps the SDK
        // again (foundations.md §9.1).
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
        // Construct + load the banner on the main actor — `BannerView` is a
        // `UIView` subclass and must be touched only from the main thread.
        // `BannerView.delegate` is `weak`; the delegate is retained in
        // `inFlightDelegates` until the SDK fires either callback, at which
        // point it self-removes (single-resume guarded by an internal lock).
        let handle = AdBannerHandle()
        let rootVC = await MainActor.run { Self.resolveRootViewController() }

        let bannerView: BannerView = await MainActor.run {
            let view = BannerView(adSize: AdSizeBanner)
            view.adUnitID = bannerAdUnitID
            view.rootViewController = rootVC
            return view
        }

        // TODO(v2.5.x): dispose(handle:) accessor to clear liveBanners
        // once the caller is done with the view. Current behavior intentionally
        // retains the BannerView for the handle's lifetime (impl-notes D3).
        liveBanners.withLock { $0[handle.id] = bannerView }

        // Holder lets the cancellation handler reach the per-load delegate that
        // is constructed inside the continuation closure. The delegate's own
        // `OSAllocatedUnfairLock<Bool>` single-resume guard (`hasResumed`) makes
        // cancel-vs-callback races safe — whichever fires first wins, the other
        // is a no-op.
        let delegateHolder = OSAllocatedUnfairLock<BannerLoadDelegate?>(initialState: nil)

        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    let delegate = BannerLoadDelegate { [weak self] result in
                        guard let self else { return }
                        // Drop the delegate retain so it (and the continuation
                        // capture chain) can deallocate.
                        self.inFlightDelegates.withLock { set in
                            // Identity-based removal — `BannerLoadDelegate: NSObject` so `Set.remove(_:)`
                            // uses NSObject identity hashing (`hash` + `isEqual:`).
                            set.remove(result.delegate)
                        }
                        switch result.outcome {
                        case .success:
                            continuation.resume(returning: ())
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }
                    delegateHolder.withLock { $0 = delegate }
                    inFlightDelegates.withLock { $0.insert(delegate) }
                    Task { @MainActor in
                        bannerView.delegate = delegate
                        bannerView.load(Request())
                    }
                }
            } onCancel: {
                // Reuse the delegate's existing single-resume guard — invoking
                // `cancel()` routes through `resumeOnce`, so whichever of
                // cancel / didReceive / didFail wins, the others are no-ops.
                // The completion closure handles `inFlightDelegates` cleanup;
                // we just need to drop the `BannerView` from `liveBanners`.
                let delegate = delegateHolder.withLock { $0 }
                delegate?.cancel()
                self.liveBanners.withLock { $0.removeValue(forKey: handle.id) }
            }
            setCachedStatus(.loaded(handle))
            return handle
        } catch {
            // Release the view we never got a successful load for.
            liveBanners.withLock { $0.removeValue(forKey: handle.id) }
            let reason = String(describing: error)
            setCachedStatus(.failed(reason: reason))
            throw AdMobBridgeError.loadFailed(reason: reason)
        }
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

    #if canImport(GoogleMobileAds) && canImport(UIKit)
    /// Resolve the foreground-active `UIWindowScene`'s key window's root view
    /// controller. AdMob requires `rootViewController` only when the user taps
    /// the ad (click-through presentation); ad fetch itself succeeds with
    /// `nil` but click-through silently fails. Returning the key window's RVC
    /// is the documented Google recommendation
    /// (https://developers.google.com/admob/ios/banner).
    @MainActor
    private static func resolveRootViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
        let active = scenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
            ?? scenes.compactMap({ $0 as? UIWindowScene }).first
        return active?.windows.first(where: { $0.isKeyWindow })?.rootViewController
            ?? active?.windows.first?.rootViewController
    }
    #endif
}

#if canImport(GoogleMobileAds)
// MARK: - BannerLoadDelegate
//
// Per-load delegate that bridges `BannerViewDelegate`'s two terminal callbacks
// into a single Swift `Result`. AdMob's contract fires at most one of
// `bannerViewDidReceiveAd` / `bannerView(_:didFailToReceiveAdWithError:)` per
// load, but the implementation belt-and-braces guards against double-fire via
// an `OSAllocatedUnfairLock<Bool>` single-resume flag.

internal final class BannerLoadDelegate: NSObject, BannerViewDelegate, @unchecked Sendable {
    internal struct CompletionResult {
        let delegate: BannerLoadDelegate
        let outcome: Result<Void, Error>
    }

    private let hasResumed = OSAllocatedUnfairLock<Bool>(initialState: false)
    private let onComplete: @Sendable (CompletionResult) -> Void

    internal init(onComplete: @escaping @Sendable (CompletionResult) -> Void) {
        self.onComplete = onComplete
    }

    private func resumeOnce(_ outcome: Result<Void, Error>) {
        let shouldFire = hasResumed.withLock { fired -> Bool in
            guard !fired else { return false }
            fired = true
            return true
        }
        guard shouldFire else { return }
        onComplete(CompletionResult(delegate: self, outcome: outcome))
    }

    internal func bannerViewDidReceiveAd(_ bannerView: BannerView) {
        resumeOnce(.success(()))
    }

    internal func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
        resumeOnce(.failure(error))
    }

    /// Invoked from `withTaskCancellationHandler.onCancel` when the awaiting
    /// task is cancelled before the SDK fires either terminal callback.
    /// Routes through the same `resumeOnce` guard so cancel-vs-callback races
    /// resolve to whichever path arrives first.
    internal func cancel() {
        resumeOnce(.failure(CancellationError()))
    }
}
#endif

// `final class` + `NSLock`-guarded state + `nonisolated(unsafe)` is the same
// `@unchecked Sendable` pattern used by `FakeStoreKitBridge` (v2.1) and
// `AdPresentationAnchor` (v2.0). Documented exception to strict concurrency:
// the live SDK fires callbacks on arbitrary queues, so an `actor` shape would
// require trampolining every delegate event — the lock is simpler and
// equivalent.
extension LiveAdMobBridge: @unchecked Sendable {}
