import Testing
import Foundation
import SwiftUI
@testable import AdsAdMob
import MonetizationCore
import MonetizationUI

// #441: the seam that lets the loaded banner view cross AdsAdMob →
// MonetizationUI as a type-erased `AnyView`. These tests pin the provider's
// `BannerViewProviding` conformance forwarding to the bridge, and the
// DEBUG-test / Release-prod ad-unit-id split inside `LiveAdMobBridge`.
@Suite("AdsAdMob — BannerViewProviding seam (#441)")
struct BannerViewProvidingTests {

    @MainActor
    @Test func fakeBridge_returnsNilHost_soSlotFallsBack() async throws {
        // The fake serves no real ad → no view. The shared `BannerSlotView`
        // renders an honest fallback (nothing in the rect) instead of a live
        // banner. We assert the provider forwards the bridge's nil through.
        let bridge = FakeAdMobBridge()
        let provider = LiveAdMobAdProvider(bridge: bridge)
        try await provider.initialize()
        try await provider.refreshBanner()

        let host: any BannerViewProviding = provider
        let view = host.bannerView(for: AdBannerHandle())
        #expect(view == nil)
    }

    @Test func liveProvider_conformsToBannerViewProviding() async {
        // Compile-time + runtime guarantee that the public `LiveAdMobAdProvider`
        // is a `BannerViewProviding` — this is the cast SudokuUI / MinesweeperUI
        // perform (`adProvider as? any BannerViewProviding`) without importing
        // AdsAdMob.
        let provider = LiveAdMobAdProvider(bridge: FakeAdMobBridge())
        #expect((provider as Any) is any BannerViewProviding)
    }

    @Test func debugBuild_overridesInjectedUnitID_withGoogleTestUnit() {
        // In DEBUG, the bridge must ignore the injected (possibly production)
        // id and serve Google's universal test creative — a dev / sim build can
        // never request prod ads. (Release reads the real id; not exercised
        // here because the package builds DEBUG under `swift test`.)
        #if DEBUG
        let bridge = LiveAdMobBridge(bannerAdUnitID: "ca-app-pub-PRODUCTION/0000000000")
        #expect(bridge.effectiveBannerAdUnitID == LiveAdMobBridge.debugTestBannerAdUnitID)
        #endif
    }
}
