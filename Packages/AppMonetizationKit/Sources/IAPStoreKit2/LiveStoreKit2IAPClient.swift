public import MonetizationCore

// MARK: - LiveStoreKit2IAPClient
//
// Production `IAPClient` implementation backed by StoreKit 2. Talks only to
// the `StoreKitBridge` seam — no direct StoreKit imports here — so behavior
// is fully unit-testable with `FakeStoreKitBridge`.
//
// Concurrency: `actor` because the client maintains a small piece of mutable
// state (the latest known entitlement set, used to stamp `isPurchased` on
// fetched products). All mutation goes through actor isolation.

public actor LiveStoreKit2IAPClient: IAPClient {
    private let bridge: any StoreKitBridge
    private let knownProductIds: Set<String>

    // MARK: Init

    /// Production initializer — wraps the real StoreKit 2 globals via
    /// `LiveStoreKitBridge` and fetches the canonical `IAPProductIDs.all`
    /// set on every `availableProducts()` call.
    public init() {
        self.bridge = LiveStoreKitBridge()
        self.knownProductIds = IAPProductIDs.all
    }

    /// Test-only initializer — injects a bridge fake and an explicit
    /// product-ID set. `internal` so production callers never see it.
    internal init(bridge: any StoreKitBridge, knownProductIds: Set<String>) {
        self.bridge = bridge
        self.knownProductIds = knownProductIds
    }

    // MARK: IAPClient — availableProducts

    public func availableProducts() async throws -> [IAPProduct] {
        let products = try await bridge.products(for: knownProductIds)
        let entitled = await bridge.currentEntitlements()
        return products.map { product in
            IAPProductMapper.map(product, isPurchased: entitled.contains(product.id))
        }
    }

    // MARK: IAPClient — purchase

    public func purchase(_ productId: String) async throws -> IAPPurchaseResult {
        let outcome = try await bridge.purchase(productId: productId)
        switch outcome {
        case .success(let id):
            // Refetch the product so the returned `IAPProduct` carries the
            // current display fields and the freshly-flipped entitlement.
            let products = try await bridge.products(for: [id])
            let entitled = await bridge.currentEntitlements()
            guard let product = products.first else {
                // Edge: purchase succeeded but the catalog lookup failed.
                // Synthesize a minimal product carrying the verified ID so
                // upstream still gets `.success` with a usable handle.
                let synthesized = IAPProduct(
                    id: id,
                    displayName: id,
                    displayPrice: "",
                    isPurchased: true
                )
                return .success(synthesized)
            }
            return .success(
                IAPProductMapper.map(product, isPurchased: entitled.contains(id))
            )
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        case .failed(let reason):
            return .failed(reason: reason)
        }
    }

    // MARK: IAPClient — restorePurchases

    public func restorePurchases() async throws -> [IAPProduct] {
        try await bridge.sync()
        let entitled = await bridge.currentEntitlements()
        // Restore only surfaces previously-purchased products. Fetch the
        // catalog for the entitled set so callers get full display fields.
        guard !entitled.isEmpty else { return [] }
        let products = try await bridge.products(for: entitled)
        return products.map { product in
            IAPProductMapper.map(product, isPurchased: true)
        }
    }

    // MARK: IAPClient — purchaseUpdates

    public nonisolated func purchaseUpdates() -> AsyncStream<IAPPurchaseEvent> {
        let upstream = bridge.transactionUpdates()
        return AsyncStream { continuation in
            let task = Task {
                for await event in upstream {
                    let mapped: IAPPurchaseEvent
                    switch event {
                    case .purchased(let id):
                        mapped = .purchased(productId: id)
                    case .revoked(let id):
                        mapped = .revoked(productId: id)
                    }
                    continuation.yield(mapped)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
