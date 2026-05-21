// swiftlint:disable identifier_name

import Testing
@testable import IAPStoreKit2
import MonetizationCore

// MARK: - PurchaseFlowTests

@Suite("IAPStoreKit2 — purchase flow")
struct PurchaseFlowTests {
    // MARK: purchase

    @Test("purchase success returns .success carrying a purchased IAPProduct")
    func purchaseSuccess() async throws {
        let bridge = makeBridgeWithRemoveAdsCatalog()
        bridge.setPurchaseOutcome(
            for: IAPProductIDs.removeAds,
            outcome: .success(productId: IAPProductIDs.removeAds)
        )
        bridge.setEntitlements([IAPProductIDs.removeAds])
        let client = makeClient(bridge)

        let result = try await client.purchase(IAPProductIDs.removeAds)
        switch result {
        case .success(let product):
            #expect(product.id == IAPProductIDs.removeAds)
            #expect(product.isPurchased == true)
        default:
            Issue.record("expected .success, got \(result)")
        }
        #expect(bridge.purchaseCallCount == 1)
    }

    @Test("purchase userCancelled surfaces as .userCancelled")
    func purchaseUserCancelled() async throws {
        let bridge = makeBridgeWithRemoveAdsCatalog()
        bridge.setPurchaseOutcome(for: IAPProductIDs.removeAds, outcome: .userCancelled)
        let client = makeClient(bridge)

        let result = try await client.purchase(IAPProductIDs.removeAds)
        #expect(result == .userCancelled)
    }

    @Test("purchase pending surfaces as .pending")
    func purchasePending() async throws {
        let bridge = makeBridgeWithRemoveAdsCatalog()
        bridge.setPurchaseOutcome(for: IAPProductIDs.removeAds, outcome: .pending)
        let client = makeClient(bridge)

        let result = try await client.purchase(IAPProductIDs.removeAds)
        #expect(result == .pending)
    }

    @Test("purchase failed surfaces .failed with reason")
    func purchaseFailed() async throws {
        let bridge = makeBridgeWithRemoveAdsCatalog()
        bridge.setPurchaseOutcome(
            for: IAPProductIDs.removeAds,
            outcome: .failed(reason: "boom")
        )
        let client = makeClient(bridge)

        let result = try await client.purchase(IAPProductIDs.removeAds)
        #expect(result == .failed(reason: "boom"))
    }

    @Test("purchase rethrows underlying bridge errors")
    func purchaseRethrows() async {
        struct DummyError: Error {}
        let bridge = makeBridgeWithRemoveAdsCatalog()
        bridge.setPurchaseError(DummyError())
        let client = makeClient(bridge)

        await #expect(throws: DummyError.self) {
            _ = try await client.purchase(IAPProductIDs.removeAds)
        }
    }

    // MARK: restorePurchases

    @Test("restorePurchases calls sync and returns entitled products with isPurchased=true")
    func restoreSuccess() async throws {
        let bridge = makeBridgeWithRemoveAdsCatalog()
        bridge.setEntitlements([IAPProductIDs.removeAds])
        let client = makeClient(bridge)

        let restored = try await client.restorePurchases()
        #expect(bridge.syncCallCount == 1)
        #expect(restored.count == 1)
        #expect(restored.first?.id == IAPProductIDs.removeAds)
        #expect(restored.first?.isPurchased == true)
    }

    @Test("restorePurchases returns empty when no entitlements")
    func restoreEmpty() async throws {
        let bridge = makeBridgeWithRemoveAdsCatalog()
        bridge.setEntitlements([])
        let client = makeClient(bridge)

        let restored = try await client.restorePurchases()
        #expect(restored.isEmpty)
        #expect(bridge.syncCallCount == 1)
    }

    @Test("restorePurchases rethrows sync errors")
    func restoreRethrows() async {
        struct DummyError: Error {}
        let bridge = makeBridgeWithRemoveAdsCatalog()
        bridge.setSyncError(DummyError())
        let client = makeClient(bridge)

        await #expect(throws: DummyError.self) {
            _ = try await client.restorePurchases()
        }
    }

    // MARK: purchaseUpdates

    @Test("purchaseUpdates pipes bridge .purchased event through as IAPPurchaseEvent.purchased")
    func updatesPipePurchased() async throws {
        let bridge = makeBridgeWithRemoveAdsCatalog()
        let client = makeClient(bridge)
        let stream = client.purchaseUpdates()

        bridge.emit(.purchased(productId: IAPProductIDs.removeAds))
        bridge.finishUpdates()

        var collected: [IAPPurchaseEvent] = []
        for await event in stream {
            collected.append(event)
        }
        #expect(collected == [.purchased(productId: IAPProductIDs.removeAds)])
    }

    @Test("purchaseUpdates pipes .revoked through — used by refund / family-share drop")
    func updatesPipeRevoked() async throws {
        let bridge = makeBridgeWithRemoveAdsCatalog()
        let client = makeClient(bridge)
        let stream = client.purchaseUpdates()

        bridge.emit(.revoked(productId: IAPProductIDs.removeAds))
        bridge.finishUpdates()

        var collected: [IAPPurchaseEvent] = []
        for await event in stream {
            collected.append(event)
        }
        #expect(collected == [.revoked(productId: IAPProductIDs.removeAds)])
    }

    @Test("purchaseUpdates emits events in order")
    func updatesPreserveOrder() async throws {
        let bridge = makeBridgeWithRemoveAdsCatalog()
        let client = makeClient(bridge)
        let stream = client.purchaseUpdates()

        bridge.emit(.purchased(productId: IAPProductIDs.removeAds))
        bridge.emit(.revoked(productId: IAPProductIDs.removeAds))
        bridge.emit(.purchased(productId: IAPProductIDs.removeAds))
        bridge.finishUpdates()

        var collected: [IAPPurchaseEvent] = []
        for await event in stream {
            collected.append(event)
        }
        #expect(collected == [
            .purchased(productId: IAPProductIDs.removeAds),
            .revoked(productId: IAPProductIDs.removeAds),
            .purchased(productId: IAPProductIDs.removeAds),
        ])
    }

    @Test("purchaseUpdates() registers a single subscription against the bridge")
    func updatesSingleSubscription() {
        let bridge = makeBridgeWithRemoveAdsCatalog()
        let client = makeClient(bridge)
        _ = client.purchaseUpdates()
        #expect(bridge.transactionUpdatesCallCount == 1)
    }

    // MARK: - Helpers

    private func makeBridgeWithRemoveAdsCatalog() -> FakeStoreKitBridge {
        let bridge = FakeStoreKitBridge()
        bridge.setProduct(BridgeProduct(
            id: IAPProductIDs.removeAds,
            displayName: "Remove Ads",
            displayPrice: "NT$89"
        ))
        return bridge
    }

    private func makeClient(_ bridge: FakeStoreKitBridge) -> LiveStoreKit2IAPClient {
        LiveStoreKit2IAPClient(bridge: bridge, knownProductIds: IAPProductIDs.all)
    }
}
