import Testing
import Foundation
@testable import AdsAdMob
import MonetizationCore

// #1058: `refreshBanner()` must not reach the ad network before the provider
// is ready — i.e. before `initialize()` (which the boot coordinator only calls
// after UMP consent) has completed. Readiness opens on ANY completion, so a
// failed initialize never deadlocks a waiting refresh.

@Suite("AdsAdMob — LiveAdMobAdProvider readiness latch (#1058)", .timeLimit(.minutes(1)))
struct ProviderReadinessTests {

    @Test func refreshWaitsForInitializeThenLoads() async throws {
        let bridge = FakeAdMobBridge()
        let provider = LiveAdMobAdProvider(bridge: bridge)

        let refresh = ObservedTask { try await provider.refreshBanner() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(!refresh.isFinished, "refresh must wait for initialize() to complete, not fail fast")
        #expect(bridge.loadCallCount == 0, "refresh must not reach the bridge before initialize() completes")

        try await provider.initialize()

        let outcome = await refresh.boundedResult()
        #expect(!outcome.timedOut, "completing initialize() must release the waiting refresh")
        #expect(throws: Never.self) { try outcome.result.get() }
        #expect(bridge.loadCallCount == 1)
    }

    @Test func refreshWaitsWhileBridgeStartIsInFlight() async throws {
        let startGate = ReadinessLatch()
        let bridge = FakeAdMobBridge(startGate: startGate)
        let provider = LiveAdMobAdProvider(bridge: bridge)

        let initialize = ObservedTask { try await provider.initialize() }
        #expect(await eventually { bridge.startCallCount == 1 }, "precondition: initialize() is in flight")

        let refresh = ObservedTask { try await provider.refreshBanner() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(!refresh.isFinished, "an in-flight initialize() is not a completed one")
        #expect(bridge.loadCallCount == 0)

        startGate.open()

        #expect(await !initialize.boundedResult().timedOut)
        let outcome = await refresh.boundedResult()
        #expect(!outcome.timedOut)
        #expect(throws: Never.self) { try outcome.result.get() }
        #expect(bridge.loadCallCount == 1)
    }

    @Test func failedInitializeReleasesRefreshWithProvidersOwnFailure() async throws {
        let bridge = FakeAdMobBridge()
        bridge.setStartError(AdMobBridgeError.initializationFailed(reason: "no network"))
        let provider = LiveAdMobAdProvider(bridge: bridge)

        let refresh = ObservedTask { try await provider.refreshBanner() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(!refresh.isFinished, "refresh must wait for initialize() to complete")

        await #expect(throws: AdMobBridgeError.self) {
            try await provider.initialize()
        }

        let outcome = await refresh.boundedResult()
        #expect(!outcome.timedOut, "a failed initialize() must still open readiness — never deadlock")
        guard case let .failure(error) = outcome.result,
              case let .initializationFailed(reason)? = error as? AdMobBridgeError else {
            Issue.record("Expected AdMobBridgeError.initializationFailed, got \(outcome.result)")
            return
        }
        #expect(reason == "not started")
        #expect(bridge.loadCallCount == 0)
    }

    @Test func awaitReadyReturnsOnlyAfterInitializeCompletes() async throws {
        let startGate = ReadinessLatch()
        let bridge = FakeAdMobBridge(startGate: startGate)
        let provider = LiveAdMobAdProvider(bridge: bridge)

        let ready = ObservedTask { try await provider.awaitReady() }
        let initialize = ObservedTask { try await provider.initialize() }
        #expect(await eventually { bridge.startCallCount == 1 })
        try await Task.sleep(for: .milliseconds(100))
        #expect(!ready.isFinished, "readiness must not open while initialize() is in flight")

        startGate.open()

        #expect(await !initialize.boundedResult().timedOut)
        let outcome = await ready.boundedResult()
        #expect(!outcome.timedOut)
        #expect(throws: Never.self) { try outcome.result.get() }
    }

    @Test func initializeRetryAfterFailureThenRefreshLoads() async throws {
        let bridge = FakeAdMobBridge()
        bridge.setStartError(AdMobBridgeError.initializationFailed(reason: "transient"))
        let provider = LiveAdMobAdProvider(bridge: bridge)

        await #expect(throws: AdMobBridgeError.self) {
            try await provider.initialize()
        }
        bridge.setStartError(nil)
        try await provider.initialize()

        let refresh = ObservedTask { try await provider.refreshBanner() }
        let outcome = await refresh.boundedResult()
        #expect(!outcome.timedOut, "readiness opened by the failure must stay open across the retry")
        #expect(throws: Never.self) { try outcome.result.get() }
        #expect(bridge.startCallCount == 2)
        #expect(bridge.loadCallCount == 1)
    }
}
