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
    /// Placeholder rendered in place of a real `displayPrice` on the
    /// synthesised fallback `IAPProduct` (M3 / v2-audit-code-polish). An
    /// em-dash is locale-neutral and renders harmlessly in any "$<price>"
    /// template; a UI showing "Receipt: —" reads as "details refreshing"
    /// rather than as a broken empty field. Hosts that want a localised
    /// "Refreshing…" string should map the empty-displayName + this
    /// sentinel in their view-layer.
    public static let unknownDisplayPricePlaceholder: String = "—"

    private let bridge: any StoreKitBridge
    private let knownProductIds: Set<String>
    private let onCatalogDesync: (@Sendable (String) -> Void)?

    // MARK: Init

    /// Production initializer — wraps the real StoreKit 2 globals via
    /// `LiveStoreKitBridge` and fetches the supplied product IDs on every
    /// `availableProducts()` call.
    ///
    /// - Parameters:
    ///   - knownProductIds: ASC product IDs to fetch. Per-app — passed in by
    ///     `AppComposition.Live` so the package can serve multiple apps
    ///     (Sudoku + Minesweeper) in the same workspace without baking
    ///     Sudoku-specific IDs into the binary.
    ///   - onCatalogDesync: Optional sink invoked with the purchased
    ///     `productId` when a post-purchase product re-fetch returns empty.
    ///     The host (`AppComposition`) wires this to `Telemetry.errorOccurred`
    ///     so catalog instability is observable instead of silently shipping
    ///     an empty `displayPrice` to the UI (M3).
    public init(
        knownProductIds: Set<String>,
        onCatalogDesync: (@Sendable (String) -> Void)? = nil
    ) {
        self.bridge = LiveStoreKitBridge()
        self.knownProductIds = knownProductIds
        self.onCatalogDesync = onCatalogDesync
    }

    /// Test-only initializer — injects a bridge fake. `internal` so production
    /// callers never see it. Production already accepts `knownProductIds` via
    /// the public init; this overload only adds the bridge seam.
    internal init(
        bridge: any StoreKitBridge,
        knownProductIds: Set<String>,
        onCatalogDesync: (@Sendable (String) -> Void)? = nil
    ) {
        self.bridge = bridge
        self.knownProductIds = knownProductIds
        self.onCatalogDesync = onCatalogDesync
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
                //
                // M3 (v2-audit-code-polish): substitute an em-dash placeholder
                // for `displayPrice` so UI consumers don't render an empty
                // string ("Receipt:  for "), and flag catalog desync through
                // the injected closure so it lights up in Telemetry.
                onCatalogDesync?(id)
                let synthesized = IAPProduct(
                    id: id,
                    displayName: id,
                    displayPrice: Self.unknownDisplayPricePlaceholder,
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
