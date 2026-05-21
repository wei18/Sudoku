import Testing
import Foundation
@testable import AdsAdMob
import MonetizationCore

@Suite("AdsAdMob — LiveAdMobAdProvider initialize")
struct AdProviderInitTests {
    @Test func initializeStartsBridgeOnce() async throws {
        let bridge = FakeAdMobBridge()
        let provider = LiveAdMobAdProvider(bridge: bridge)

        try await provider.initialize()

        #expect(bridge.startCallCount == 1)
    }

    @Test func initializeIsIdempotentAfterSuccess() async throws {
        let bridge = FakeAdMobBridge()
        let provider = LiveAdMobAdProvider(bridge: bridge)

        try await provider.initialize()
        try await provider.initialize()
        try await provider.initialize()

        #expect(bridge.startCallCount == 1)
    }

    @Test func initializeRethrowsBridgeError() async {
        let bridge = FakeAdMobBridge()
        bridge.setStartError(AdMobBridgeError.initializationFailed(reason: "no network"))
        let provider = LiveAdMobAdProvider(bridge: bridge)

        await #expect(throws: AdMobBridgeError.self) {
            try await provider.initialize()
        }
    }

    @Test func bannerStatusBeforeInitializeIsNotInitialized() async {
        let bridge = FakeAdMobBridge()
        let provider = LiveAdMobAdProvider(bridge: bridge)

        let status = await provider.bannerStatus
        #expect(status == .notInitialized)
    }

    @Test func bannerStatusAfterInitializeReflectsBridgeCache() async throws {
        let bridge = FakeAdMobBridge()
        let provider = LiveAdMobAdProvider(bridge: bridge)

        try await provider.initialize()
        // The fake's `start()` sets cached status to `.loading`.
        let status = await provider.bannerStatus
        #expect(status == .loading)
    }

    @Test func initializeFailureCanBeRetried() async throws {
        let bridge = FakeAdMobBridge()
        bridge.setStartError(AdMobBridgeError.initializationFailed(reason: "transient"))
        let provider = LiveAdMobAdProvider(bridge: bridge)

        await #expect(throws: AdMobBridgeError.self) {
            try await provider.initialize()
        }

        // Clear the error and retry — should succeed now.
        bridge.setStartError(nil)
        try await provider.initialize()
        #expect(bridge.startCallCount == 2)
    }
}
