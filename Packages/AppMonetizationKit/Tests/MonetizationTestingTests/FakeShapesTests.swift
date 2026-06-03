import Foundation
import Testing
import MonetizationCore
@testable import MonetizationTesting

// swiftlint:disable identifier_name

@Suite("FakeAdProvider — scripted behavior")
struct FakeAdProviderTests {

    @Test func defaultStatusIsNotInitialized() async {
        let fake = FakeAdProvider()
        #expect(await fake.bannerStatus == .notInitialized)
    }

    @Test func scriptedStatusSequenceAdvancesOnRefresh() async throws {
        let h1 = AdBannerHandle()
        let h2 = AdBannerHandle()
        let fake = FakeAdProvider()
        await fake.script(ScriptedAdProviderState(statusSequence: [
            .loading,
            .loaded(h1),
            .loaded(h2),
        ]))
        #expect(await fake.bannerStatus == .loading)
        try await fake.refreshBanner()
        #expect(await fake.bannerStatus == .loaded(h1))
        try await fake.refreshBanner()
        #expect(await fake.bannerStatus == .loaded(h2))
        // Past the end — last value sticks.
        try await fake.refreshBanner()
        #expect(await fake.bannerStatus == .loaded(h2))
    }

    @Test func initializeCallCountIsTracked() async throws {
        let fake = FakeAdProvider()
        try await fake.initialize()
        try await fake.initialize()
        try await fake.initialize()
        #expect(await fake.initializeCallCount == 3)
    }

    @Test func scriptedInitializeErrorThrows() async {
        enum Boom: Error, Equatable { case explode }
        let fake = FakeAdProvider(scripted: ScriptedAdProviderState(
            initializeThrows: Boom.explode
        ))
        await #expect(throws: Boom.self) {
            try await fake.initialize()
        }
    }

    @Test func disposeRecordsHandlesInOrder() async {
        let h1 = AdBannerHandle()
        let h2 = AdBannerHandle()
        let fake = FakeAdProvider()
        await fake.dispose(handle: h1)
        await fake.dispose(handle: h2)
        #expect(await fake.disposedHandles == [h1, h2])
    }
}

@Suite("FakeIAPClient — scripted behavior")
struct FakeIAPClientTests {

    private static let product = IAPProduct(
        id: "com.wei18.sudoku.iap.remove_ads",
        displayName: "Remove Ads",
        displayPrice: "$2.99",
        isPurchased: false
    )

    @Test func availableProductsReturnsScripted() async throws {
        let fake = FakeIAPClient()
        await fake.setProducts([Self.product])
        let products = try await fake.availableProducts()
        #expect(products == [Self.product])
    }

    @Test func purchaseReturnsScriptedResult() async throws {
        let fake = FakeIAPClient()
        await fake.setPurchaseResult(
            for: Self.product.id,
            result: .success(Self.product)
        )
        let result = try await fake.purchase(Self.product.id)
        #expect(result == .success(Self.product))
    }

    @Test func purchaseWithoutScriptingReportsFailure() async throws {
        let fake = FakeIAPClient()
        let result = try await fake.purchase("unknown.product")
        guard case .failed = result else {
            Issue.record("expected .failed, got \(result)")
            return
        }
    }

    @Test func restoreFlipsIsPurchasedToTrue() async throws {
        let fake = FakeIAPClient()
        await fake.setProducts([Self.product])
        let restored = try await fake.restorePurchases()
        #expect(restored.count == 1)
        #expect(restored.first?.isPurchased == true)
    }

    @Test func purchaseUpdatesDeliversEmittedEvents() async {
        let fake = FakeIAPClient()
        let stream = fake.purchaseUpdates()
        await fake.emit(.purchased(productId: Self.product.id))
        await fake.emit(.revoked(productId: Self.product.id))
        await fake.finishUpdates()

        var collected: [IAPPurchaseEvent] = []
        for await event in stream {
            collected.append(event)
        }
        #expect(collected == [
            .purchased(productId: Self.product.id),
            .revoked(productId: Self.product.id),
        ])
    }

    // N5-followup (impl-notes 2026-05-23 §未決 #3): two concurrent
    // subscribers must each receive every emitted event, matching Live
    // semantics.
    @Test func purchaseUpdatesMultipleConcurrentSubscribersAllReceive() async {
        let fake = FakeIAPClient()
        let s1 = fake.purchaseUpdates()
        let s2 = fake.purchaseUpdates()
        #expect(fake.purchaseUpdatesSubscriberCount == 2)

        await fake.emit(.purchased(productId: Self.product.id))
        await fake.emit(.revoked(productId: Self.product.id))
        await fake.finishUpdates()

        async let collected1: [IAPPurchaseEvent] = {
            var acc: [IAPPurchaseEvent] = []
            for await event in s1 { acc.append(event) }
            return acc
        }()
        async let collected2: [IAPPurchaseEvent] = {
            var acc: [IAPPurchaseEvent] = []
            for await event in s2 { acc.append(event) }
            return acc
        }()
        let (c1, c2) = await (collected1, collected2)
        let expected: [IAPPurchaseEvent] = [
            .purchased(productId: Self.product.id),
            .revoked(productId: Self.product.id),
        ]
        #expect(c1 == expected)
        #expect(c2 == expected)
    }

    @Test func purchaseUpdatesSubscriberCountDropsOnCancellation() async {
        let fake = FakeIAPClient()
        // Spawn a task that subscribes, then cancel it; the registry
        // should unregister the continuation via `onTermination`.
        let task = Task {
            for await _ in fake.purchaseUpdates() {
                // Drain — should exit on cancellation.
            }
        }
        // Give the task a beat to enter the for-await (and thus register).
        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(fake.purchaseUpdatesSubscriberCount == 1)

        task.cancel()
        // onTermination fires on cancel; allow a brief hop.
        try? await Task.sleep(nanoseconds: 20_000_000)
        await task.value
        #expect(fake.purchaseUpdatesSubscriberCount == 0)
    }
}
// swiftlint:enable identifier_name
