import Testing
import Foundation
@testable import AdsAdMob
import MonetizationCore

@Suite("AdsAdMob — LiveAdMobAdProvider banner load / refresh")
struct BannerLoadTests {
    @Test func refreshLoadsBanner() async throws {
        let bridge = FakeAdMobBridge()
        let provider = LiveAdMobAdProvider(bridge: bridge)
        try await provider.initialize()

        try await provider.refreshBanner()

        #expect(bridge.loadCallCount == 1)
        let status = await provider.bannerStatus
        if case .loaded = status {
            // Expected.
        } else {
            Issue.record("Expected .loaded, got \(status)")
        }
    }

    @Test func refreshExposesHandleFromBridge() async throws {
        let expectedHandle = AdBannerHandle()
        let bridge = FakeAdMobBridge()
        bridge.setNextHandle(expectedHandle)
        let provider = LiveAdMobAdProvider(bridge: bridge)
        try await provider.initialize()

        try await provider.refreshBanner()

        let status = await provider.bannerStatus
        #expect(status == .loaded(expectedHandle))
    }

    @Test func refreshFailureSetsFailedStatus() async throws {
        let bridge = FakeAdMobBridge()
        bridge.setLoadError(AdMobBridgeError.loadFailed(reason: "no fill"))
        let provider = LiveAdMobAdProvider(bridge: bridge)
        try await provider.initialize()

        await #expect(throws: AdMobBridgeError.self) {
            try await provider.refreshBanner()
        }

        let status = await provider.bannerStatus
        if case .failed = status {
            // Expected.
        } else {
            Issue.record("Expected .failed, got \(status)")
        }
    }

    @Test func refreshBeforeInitializeFails() async {
        let bridge = FakeAdMobBridge()
        let provider = LiveAdMobAdProvider(bridge: bridge)

        await #expect(throws: AdMobBridgeError.self) {
            try await provider.refreshBanner()
        }
        #expect(bridge.loadCallCount == 0)
    }

    @Test func refreshAfterFailureCanRecover() async throws {
        let bridge = FakeAdMobBridge()
        bridge.setLoadError(AdMobBridgeError.loadFailed(reason: "transient"))
        let provider = LiveAdMobAdProvider(bridge: bridge)
        try await provider.initialize()

        await #expect(throws: AdMobBridgeError.self) {
            try await provider.refreshBanner()
        }

        bridge.setLoadError(nil)
        try await provider.refreshBanner()

        let status = await provider.bannerStatus
        if case .loaded = status {
            // Expected.
        } else {
            Issue.record("Expected .loaded after recovery, got \(status)")
        }
        #expect(bridge.loadCallCount == 2)
    }

    @Test func consecutiveRefreshesAdvanceLoadCount() async throws {
        let bridge = FakeAdMobBridge()
        let provider = LiveAdMobAdProvider(bridge: bridge)
        try await provider.initialize()

        try await provider.refreshBanner()
        try await provider.refreshBanner()
        try await provider.refreshBanner()

        #expect(bridge.loadCallCount == 3)
    }

    @Test func statusTransitionsLoadingThenLoaded() async throws {
        let bridge = FakeAdMobBridge()
        let provider = LiveAdMobAdProvider(bridge: bridge)
        try await provider.initialize()
        let afterInit = await provider.bannerStatus
        #expect(afterInit == .loading)

        try await provider.refreshBanner()
        let afterRefresh = await provider.bannerStatus
        if case .loaded = afterRefresh {
            // Expected.
        } else {
            Issue.record("Expected .loaded after refresh, got \(afterRefresh)")
        }
    }

    @Test func bridgeFailureSurfaceAsLoadFailedReason() async throws {
        let bridge = FakeAdMobBridge()
        bridge.setLoadError(AdMobBridgeError.loadFailed(reason: "request timeout"))
        let provider = LiveAdMobAdProvider(bridge: bridge)
        try await provider.initialize()

        try? await provider.refreshBanner()

        let status = await provider.bannerStatus
        guard case let .failed(reason) = status else {
            Issue.record("Expected .failed")
            return
        }
        #expect(reason.contains("timeout"))
    }
}
