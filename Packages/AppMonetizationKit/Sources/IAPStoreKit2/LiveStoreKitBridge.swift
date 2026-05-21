internal import StoreKit

// MARK: - LiveStoreKitBridge
//
// Production `StoreKitBridge` impl. Thin adapter over Apple's StoreKit 2
// globals — no business logic lives here; everything routes through the
// bridge protocol so `LiveStoreKit2IAPClient` stays unit-testable.

internal struct LiveStoreKitBridge: StoreKitBridge {
    init() {}

    // MARK: products

    func products(for ids: Set<String>) async throws -> [BridgeProduct] {
        let products = try await Product.products(for: ids)
        return products.map { product in
            BridgeProduct(
                id: product.id,
                displayName: product.displayName,
                displayPrice: product.displayPrice
            )
        }
    }

    // MARK: entitlements

    func currentEntitlements() async -> Set<String> {
        var ids: Set<String> = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            // A non-consumable with `revocationDate != nil` is no longer
            // entitled (refunded / family-share dropped); skip.
            if transaction.revocationDate != nil { continue }
            ids.insert(transaction.productID)
        }
        return ids
    }

    // MARK: purchase

    func purchase(productId: String) async throws -> BridgePurchaseOutcome {
        // Fetch the `Product` instance first; `Product.purchase()` is only
        // callable on a fetched product. If the product disappeared from
        // ASC between launch and purchase, surface as `.failed`.
        let fetched = try await Product.products(for: [productId])
        guard let product = fetched.first else {
            return .failed(reason: "product not found: \(productId)")
        }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await transaction.finish()
                return .success(productId: transaction.productID)
            case .unverified(_, let error):
                return .failed(reason: "unverified: \(error)")
            }
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            return .failed(reason: "unknown PurchaseResult case")
        }
    }

    // MARK: sync

    func sync() async throws {
        try await AppStore.sync()
    }

    // MARK: transaction updates

    func transactionUpdates() -> AsyncStream<BridgeTransactionEvent> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .background) {
                for await result in Transaction.updates {
                    guard case .verified(let transaction) = result else {
                        // Drop unverified entries — we never adjust
                        // entitlement state on an untrusted signal.
                        continue
                    }
                    let event: BridgeTransactionEvent =
                        (transaction.revocationDate != nil)
                            ? .revoked(productId: transaction.productID)
                            : .purchased(productId: transaction.productID)
                    continuation.yield(event)
                    await transaction.finish()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
