internal import Foundation

// MARK: - NoopAdProvider
//
// Production fallback `AdProvider` for platforms where AdMob is unavailable.
// Google's `GoogleMobileAds` and `UserMessagingPlatform` SPM products ship
// iOS-only xcframeworks; on macOS the `AdsAdMob.LiveAdMobAdProvider` cannot
// be wired (the SDK is gated out of the package dep via
// `.condition(.when(platforms: [.iOS]))` in `Package.swift`).
//
// Behavior:
//   - `initialize()` is a no-op and never throws.
//   - `bannerStatus` always returns `.suppressed` — `BannerSlotView` already
//     collapses to `EmptyView()` on `.suppressed`, so the banner slot
//     disappears cleanly on macOS. This matches the design intent ("no ads
//     where the SDK is unavailable") without adding a new `AdBannerStatus`
//     case (e.g. `.unsupported`) that other call sites would have to handle.
//   - `refreshBanner()` is a no-op and never throws.
//
// Suppression precedence note: `AdGate.shouldShowBanner` is the canonical
// arbiter of "should this user see a banner right now". UI call sites consult
// the gate first; this provider's `.suppressed` is the second line of defense
// for hosts that bypass the gate (or for surface areas where the gate hasn't
// been wired yet).

public actor NoopAdProvider: AdProvider {
    public init() {}

    public var bannerStatus: AdBannerStatus {
        get async { .suppressed }
    }

    public func initialize() async throws {
        // no-op: nothing to start when the SDK is absent.
    }

    public func refreshBanner() async throws {
        // no-op: status stays `.suppressed` regardless of refresh requests.
    }
}
