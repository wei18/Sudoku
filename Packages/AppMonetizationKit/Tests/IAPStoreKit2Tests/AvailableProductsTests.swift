// swiftlint:disable identifier_name

import Testing
@testable import IAPStoreKit2

// MARK: - IAPProductMapper unit tests (pure function — no client needed)

@Suite("IAPStoreKit2 — IAPProductMapper")
struct IAPProductMapperTests {
    @Test("maps id / displayName / displayPrice straight through")
    func mapsFieldsStraightThrough() {
        let bridge = BridgeProduct(
            id: "com.wei18.sudoku.iap.remove_ads",
            displayName: "Remove Ads",
            displayPrice: "NT$89"
        )
        let mapped = IAPProductMapper.map(bridge, isPurchased: false)
        #expect(mapped.id == "com.wei18.sudoku.iap.remove_ads")
        #expect(mapped.displayName == "Remove Ads")
        #expect(mapped.displayPrice == "NT$89")
    }

    @Test("isPurchased false flag passes through")
    func unpurchasedFlag() {
        let bridge = BridgeProduct(id: "x", displayName: "X", displayPrice: "$1")
        let mapped = IAPProductMapper.map(bridge, isPurchased: false)
        #expect(mapped.isPurchased == false)
    }

    @Test("isPurchased true flag passes through")
    func purchasedFlag() {
        let bridge = BridgeProduct(id: "x", displayName: "X", displayPrice: "$1")
        let mapped = IAPProductMapper.map(bridge, isPurchased: true)
        #expect(mapped.isPurchased == true)
    }

    @Test("locale-formatted price strings are preserved verbatim")
    func localePriceVerbatim() {
        let cases: [(String, String)] = [
            ("ntd", "NT$89"),
            ("usd", "$2.99"),
            ("jpy", "¥360"),
            ("eur", "€2,99"),
        ]
        for (id, price) in cases {
            let bridge = BridgeProduct(id: id, displayName: id, displayPrice: price)
            let mapped = IAPProductMapper.map(bridge, isPurchased: false)
            #expect(mapped.displayPrice == price)
        }
    }
}

// MARK: - LiveStoreKit2IAPClient.availableProducts tests (fake bridge)

@Suite("IAPStoreKit2 — availableProducts")
struct AvailableProductsTests {
    @Test("returns products mapped from the bridge, isPurchased=false when not entitled")
    func returnsUnpurchasedWhenNoEntitlement() async throws {
        let bridge = FakeStoreKitBridge()
        bridge.setProduct(BridgeProduct(
            id: IAPProductIDs.removeAds,
            displayName: "Remove Ads",
            displayPrice: "NT$89"
        ))
        bridge.setEntitlements([])
        let client = LiveStoreKit2IAPClient(
            bridge: bridge,
            knownProductIds: IAPProductIDs.all
        )

        let products = try await client.availableProducts()
        #expect(products.count == 1)
        #expect(products.first?.id == IAPProductIDs.removeAds)
        #expect(products.first?.isPurchased == false)
        #expect(bridge.productsCallCount == 1)
        #expect(bridge.currentEntitlementsCallCount == 1)
    }

    @Test("returns isPurchased=true when product appears in currentEntitlements")
    func stampsPurchasedFromEntitlements() async throws {
        let bridge = FakeStoreKitBridge()
        bridge.setProduct(BridgeProduct(
            id: IAPProductIDs.removeAds,
            displayName: "Remove Ads",
            displayPrice: "$2.99"
        ))
        bridge.setEntitlements([IAPProductIDs.removeAds])
        let client = LiveStoreKit2IAPClient(
            bridge: bridge,
            knownProductIds: IAPProductIDs.all
        )

        let products = try await client.availableProducts()
        #expect(products.first?.isPurchased == true)
    }

    @Test("empty product list when bridge returns nothing")
    func emptyWhenBridgeEmpty() async throws {
        let bridge = FakeStoreKitBridge()
        let client = LiveStoreKit2IAPClient(
            bridge: bridge,
            knownProductIds: IAPProductIDs.all
        )
        let products = try await client.availableProducts()
        #expect(products.isEmpty)
    }

    @Test("rethrows products fetch errors")
    func rethrowsProductsError() async {
        struct DummyError: Error {}
        let bridge = FakeStoreKitBridge()
        bridge.setProductsError(DummyError())
        let client = LiveStoreKit2IAPClient(
            bridge: bridge,
            knownProductIds: IAPProductIDs.all
        )

        await #expect(throws: DummyError.self) {
            _ = try await client.availableProducts()
        }
    }
}

// MARK: - IAPProductIDs constants

@Suite("IAPStoreKit2 — IAPProductIDs")
struct IAPProductIDsTests {
    @Test("removeAds matches App Store Connect identifier")
    func removeAdsIdentifier() {
        #expect(IAPProductIDs.removeAds == "com.wei18.sudoku.iap.remove_ads")
    }

    @Test("all set includes removeAds")
    func allIncludesRemoveAds() {
        #expect(IAPProductIDs.all.contains(IAPProductIDs.removeAds))
    }
}
