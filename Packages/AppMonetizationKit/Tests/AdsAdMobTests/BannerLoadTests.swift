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

    // #1058: refresh before initialize() now waits for readiness instead of
    // failing fast. Bounded: the waiting refresh is cancelled, so a latch that
    // never releases fails this test rather than hanging the suite.
    @Test(.timeLimit(.minutes(1)))
    func refreshBeforeInitializeWaitsWithoutReachingBridge() async throws {
        let bridge = FakeAdMobBridge()
        let provider = LiveAdMobAdProvider(bridge: bridge)

        let refresh = ObservedTask { try await provider.refreshBanner() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(!refresh.isFinished, "refresh must wait for initialize(), not fail fast")

        refresh.cancel()

        let outcome = await refresh.boundedResult()
        #expect(!outcome.timedOut)
        #expect(throws: CancellationError.self) { try outcome.result.get() }
        #expect(bridge.loadCallCount == 0)
        #expect(await provider.bannerStatus == .notInitialized)
    }

    // #1058 PM 1 seam 3: a load cancelled in flight is not a failure. The
    // provider must throw `CancellationError` and put its status back to what
    // it was before the call — never `.failed` ("Ad unavailable").
    @Test(.timeLimit(.minutes(1)))
    func cancelledInFlightLoadRestoresPreviousStatus() async throws {
        let firstHandle = AdBannerHandle()
        let bridge = FakeAdMobBridge()
        bridge.setNextHandle(firstHandle)
        let provider = LiveAdMobAdProvider(bridge: bridge)
        try await provider.initialize()
        try await provider.refreshBanner()
        let before = await provider.bannerStatus
        #expect(before == .loaded(firstHandle), "precondition: a loaded banner")

        bridge.setLoadGate(ReadinessLatch())
        let refresh = ObservedTask { try await provider.refreshBanner() }
        #expect(await eventually { bridge.loadCallCount == 2 }, "precondition: second load in flight")

        refresh.cancel()

        let outcome = await refresh.boundedResult()
        #expect(!outcome.timedOut)
        #expect(throws: CancellationError.self) { try outcome.result.get() }
        let after = await provider.bannerStatus
        #expect(after == before, "a cancelled load must restore the prior status, got \(after)")
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

        _ = try? await provider.refreshBanner()

        let status = await provider.bannerStatus
        guard case let .failed(reason) = status else {
            Issue.record("Expected .failed")
            return
        }
        #expect(reason.contains("timeout"))
    }
}
