// swiftlint:disable identifier_name trailing_comma

import Foundation
import Testing
import MonetizationCore
@testable import MonetizationTesting

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
}
