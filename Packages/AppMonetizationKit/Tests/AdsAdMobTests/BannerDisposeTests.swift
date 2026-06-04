import Testing
import Foundation
@testable import AdsAdMob
import MonetizationCore

@Suite("AdsAdMob — LiveAdMobAdProvider banner dispose (#221)")
struct BannerDisposeTests {
    @Test func disposeForwardsHandleToBridge() async throws {
        let handle = AdBannerHandle()
        let bridge = FakeAdMobBridge()
        bridge.setNextHandle(handle)
        let provider = LiveAdMobAdProvider(bridge: bridge)
        try await provider.initialize()
        try await provider.refreshBanner()

        await provider.dispose(handle: handle)

        #expect(bridge.disposedHandles == [handle])
    }

    @Test func disposeClearsLoadedStatusForSameHandle() async throws {
        let handle = AdBannerHandle()
        let bridge = FakeAdMobBridge()
        bridge.setNextHandle(handle)
        let provider = LiveAdMobAdProvider(bridge: bridge)
        try await provider.initialize()
        try await provider.refreshBanner()
        #expect(await provider.bannerStatus == .loaded(handle))

        await provider.dispose(handle: handle)

        // Post-dispose status is `.disposed`, not `.notInitialized`: the SDK is
        // still initialized, only this handle's view was released (#276).
        #expect(await provider.bannerStatus == .disposed)
    }

    @Test func disposeOfUnrelatedHandleLeavesLoadedStatusIntact() async throws {
        let loaded = AdBannerHandle()
        let other = AdBannerHandle()
        let bridge = FakeAdMobBridge()
        bridge.setNextHandle(loaded)
        let provider = LiveAdMobAdProvider(bridge: bridge)
        try await provider.initialize()
        try await provider.refreshBanner()

        await provider.dispose(handle: other)

        // Bridge still receives the dispose request, but the surfaced
        // `.loaded(loaded)` status is untouched because the disposed handle
        // is not the one currently displayed.
        #expect(bridge.disposedHandles == [other])
        #expect(await provider.bannerStatus == .loaded(loaded))
    }

    @Test func disposeWithoutLoadIsSafeNoop() async throws {
        let bridge = FakeAdMobBridge()
        let provider = LiveAdMobAdProvider(bridge: bridge)
        try await provider.initialize()

        await provider.dispose(handle: AdBannerHandle())

        #expect(bridge.disposedHandles.count == 1)
        #expect(await provider.bannerStatus == .loading)
    }
}
