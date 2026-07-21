internal import Foundation
internal import MonetizationCore
internal import os
internal import SwiftUI

#if canImport(GoogleMobileAds)
internal import GoogleMobileAds
#endif

#if canImport(UIKit)
internal import UIKit
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
    // AdMob banner ad unit ID. Per-app — `SudokuAppComposition.Live` selects the
    // value (DEBUG: Google universal test unit; Release: the app's production
    // unit from AdMob console) so this package can serve multiple apps in
    // the same workspace without baking Sudoku-specific IDs into the binary.
    // The `GADApplicationIdentifier` in each app's `Info.plist` follows the
    // same DEBUG ↔ Release swap point.
    private let bannerAdUnitID: String

    /// Test seam (#441): the ad-unit-id the bridge will actually request with,
    /// after the DEBUG test-unit override. Lets `BannerViewProvidingTests`
    /// assert the Debug-test / Release-prod split without booting the SDK.
    internal var effectiveBannerAdUnitID: String { bannerAdUnitID }

    #if canImport(GoogleMobileAds)
    // `OSAllocatedUnfairLock` is the Swift 6 strict-concurrency-safe equivalent
    // of `NSLock` — its `withLock` overloads are `nonisolated` and callable
    // from async contexts, unlike `NSLock.lock()` which is restricted.
    //
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

    /// Google's UNIVERSAL TEST banner unit id (publicly documented, safe to
    /// commit). DEBUG builds ALWAYS serve test creatives against this id so a
    /// dev / simulator build can never accidentally request production ads
    /// against the live app id. Release reads the real per-app prod id from
    /// `Info.plist` (`GADBannerUnitID`, injected from `Tuist/AdMob.xcconfig`),
    /// which `SudokuAppComposition` passes into `bannerAdUnitID`. (#441 — user
    /// decision: prod ids in Release / TestFlight are intended.)
    /// https://developers.google.com/admob/ios/test-ads#sample_ad_units
    internal static let debugTestBannerAdUnitID = "ca-app-pub-3940256099942544/2934735716"

    internal init(bannerAdUnitID: String) {
        #if DEBUG
        // Ignore the injected (possibly production) id in DEBUG — test creatives only.
        self.bannerAdUnitID = Self.debugTestBannerAdUnitID
        #else
        self.bannerAdUnitID = bannerAdUnitID
        #endif
    }

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
                        _ = self.inFlightDelegates.withLock { set in
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
                    _ = inFlightDelegates.withLock { $0.insert(delegate) }
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
                _ = self.liveBanners.withLock { $0.removeValue(forKey: handle.id) }
            }
            return handle
        } catch {
            // Release the view we never got a successful load for.
            _ = liveBanners.withLock { $0.removeValue(forKey: handle.id) }
            let reason = String(describing: error)
            throw AdMobBridgeError.loadFailed(reason: reason)
        }
        #else
        throw AdMobBridgeError.unsupportedPlatform
        #endif
    }

    internal func dispose(handle: AdBannerHandle) async {
        #if canImport(GoogleMobileAds)
        // Drop the strong retain held in `liveBanners`. `removeValue` returns
        // the view (if present) so the only remaining reference is local —
        // tear it down on the main actor, then let it deallocate. Unknown /
        // already-disposed handles return nil and no-op.
        let bannerView = liveBanners.withLock { $0.removeValue(forKey: handle.id) }
        guard let bannerView else { return }
        await MainActor.run {
            bannerView.delegate = nil
            bannerView.removeFromSuperview()
        }
        #endif
        // Non-iOS / SDK-absent builds retain no per-handle state — no-op.
    }

    @MainActor
    internal func bannerView(for handle: AdBannerHandle) -> AnyView? {
        #if canImport(GoogleMobileAds)
        // Look up the retained `BannerView` for this handle and wrap it in a
        // `UIViewRepresentable`. The SDK view never escapes AdsAdMob — only the
        // type-erased `AnyView` crosses into MonetizationUI (foundations.md §9.1).
        guard let bannerView = liveBanners.withLock({ $0[handle.id] }) else { return nil }
        return AnyView(BannerViewRepresentable(bannerView: bannerView))
        #else
        return nil
        #endif
    }

    // MARK: - Internal helpers

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
        let outcome: Result<Void, any Error>
    }

    private let hasResumed = OSAllocatedUnfairLock<Bool>(initialState: false)
    private let onComplete: @Sendable (CompletionResult) -> Void

    internal init(onComplete: @escaping @Sendable (CompletionResult) -> Void) {
        self.onComplete = onComplete
    }

    private func resumeOnce(_ outcome: Result<Void, any Error>) {
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

    internal func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: any Error) {
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

// MARK: - BannerViewRepresentable
//
// SwiftUI host for a live `BannerView`. The bridge already owns the view's
// lifecycle (retained in `liveBanners`, torn down in `dispose`); this
// representable just mounts it. It is wrapped in `AnyView` by
// `bannerView(for:)` so the SDK type never crosses the AdsAdMob border
// (foundations.md §9.1). `#if canImport(UIKit)` keeps this iOS-only.

#if canImport(UIKit)
internal struct BannerViewRepresentable: UIViewRepresentable {
    let bannerView: BannerView

    func makeUIView(context: Context) -> BannerView {
        bannerView
    }

    func updateUIView(_ uiView: BannerView, context: Context) {
        // The bridge owns the view's content (ad load); no per-update mutation.
    }
}
#endif
#endif

// `final class` + `NSLock`-guarded state + `nonisolated(unsafe)` is the same
// `@unchecked Sendable` pattern used by `FakeStoreKitBridge` (v2.1).
// Documented exception to strict concurrency: the live SDK fires callbacks on
// arbitrary queues, so an `actor` shape would require trampolining every
// delegate event — the lock is simpler and equivalent.
extension LiveAdMobBridge: @unchecked Sendable {}
