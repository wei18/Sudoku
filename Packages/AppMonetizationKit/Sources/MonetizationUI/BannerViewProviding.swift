// BannerViewProviding — the seam that lets a loaded banner view cross the
// AdsAdMob → MonetizationUI border WITHOUT leaking the Google Mobile Ads SDK
// (#441, foundations.md §9.1).
//
// The contract forbids `GADBannerView` (now `BannerView`) from crossing the
// AdsAdMob target border. `AnyView` is a SwiftUI type, not a GoogleMobileAds
// type, so type-erasing the live banner host into an `AnyView` honours the
// isolation rule: the SDK view is constructed and retained entirely inside
// AdsAdMob; only an opaque SwiftUI view escapes.
//
// `LiveAdMobAdProvider` (AdsAdMob) conforms to this. The shared `BannerSlotView`
// holds an optional `any BannerViewProviding` and, on `.loaded(handle)`, asks it
// for the view to render. Fakes / macOS `NoopAdProvider` pass `nil` — the slot
// then falls back to an honest caption instead of a live ad host.

public import MonetizationCore
public import SwiftUI

public protocol BannerViewProviding: Sendable {
    /// Returns the SwiftUI view that renders the banner backing `handle`, or
    /// `nil` if no live view is available for it (unknown / disposed handle, or
    /// a provider that serves no real ads). The returned view is the host's
    /// responsibility to size to the 50pt slot contract — the slot frames it.
    ///
    /// `@MainActor` (the underlying SDK view is a `UIView`); the protocol itself
    /// stays un-isolated so an `actor` (`LiveAdMobAdProvider`) can conform.
    @MainActor
    func bannerView(for handle: AdBannerHandle) -> AnyView?
}
