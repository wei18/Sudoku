// BannerSessionModelSuppressionOrderTests — pins the #1078 2g ordering in
// `runStart()`: the provider's suppression is resolved BEFORE an open gate is
// published, so `isVisible` never reads true on a host whose provider cannot
// serve (macOS `NoopAdProvider`). Before 2g the model published
// `shouldShow = true` and only then awaited `providerCanServe`, which painted
// one 50pt spinner band on a macOS cold launch and then collapsed it.
//
// The window is made observable by holding the provider's `bannerStatus` read
// on a latch: the test samples `isVisible` while `runStart()` is suspended in
// that read. With the old order the sample is `true`; with 2g it is `false`,
// and it stays `false` after the read returns `.suppressed`.

import Foundation
import Testing
import MonetizationCore
import MonetizationTesting
@testable import MonetizationUI

/// Reports `.suppressed`, but only after the test releases the read.
private actor HeldStatusSuppressedAdProvider: AdProvider {
    nonisolated let statusRequested = ReadinessLatch()
    nonisolated let release = ReadinessLatch()
    private(set) var refreshCallCount = 0

    func initialize() async throws {}

    func awaitReady() async throws {}

    var bannerStatus: AdBannerStatus {
        get async {
            statusRequested.open()
            try? await release.wait()
            return .suppressed
        }
    }

    func refreshBanner() async throws -> AdBannerHandle {
        refreshCallCount += 1
        return AdBannerHandle()
    }

    func dispose(handle: AdBannerHandle) async {}
}

@Suite("BannerSessionModel — suppression resolved before publishing (#1078 2g)")
@MainActor
struct BannerSessionModelSuppressionOrderTests {

    @Test("an open gate on a suppressed provider is never visible, not even for one frame")
    func openGateOnSuppressedProviderIsNeverVisible() async throws {
        let provider = HeldStatusSuppressedAdProvider()
        let (gate, _) = SessionFixture.gate(SessionFixture.openState)
        let model = BannerSessionModel(adProvider: provider, adGate: gate, now: { SessionFixture.today })
        model.register(BannerSlotID())

        var samples: [Bool] = []
        let start = Task { await model.start() }

        // `runStart()` is now suspended inside the held status read: this is
        // the frame the old order published `shouldShow = true` into.
        try await provider.statusRequested.wait()
        samples.append(model.isVisible)

        provider.release.open()
        await start.value
        samples.append(model.isVisible)

        #expect(samples == [false, false], "isVisible must never be observed true: \(samples)")
        #expect(model.shouldShow == true, "the open gate is still published once suppression is known")
        #expect(model.isVisible == false)
        #expect(await provider.refreshCallCount == 0, "a suppressed provider is never asked to load")
    }

    @Test("a closed gate publishes false without consulting the provider")
    func closedGateNeverReadsProviderStatus() async {
        let provider = HeldStatusSuppressedAdProvider()
        let (gate, _) = SessionFixture.gate(SessionFixture.dismissedTodayState)
        let model = BannerSessionModel(adProvider: provider, adGate: gate, now: { SessionFixture.today })

        await model.start()

        #expect(model.shouldShow == false)
        #expect(model.isVisible == false)
        #expect(!provider.statusRequested.isOpen, "a closed gate must not read the provider's status")
    }
}
