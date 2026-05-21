internal import MonetizationCore

// MARK: - StoreKitBridge
//
// Test seam over Apple's StoreKit 2 global API surface. `LiveStoreKit2IAPClient`
// talks to the bridge only — `Product.products(for:)`, `AppStore.sync()`,
// `Transaction.currentEntitlements`, and `Transaction.updates` are all
// untestable globals, so we keep them behind this protocol.
//
// Production wiring uses `LiveStoreKitBridge`. Tests inject a fake.

internal protocol StoreKitBridge: Sendable {
    /// Fetch products from the App Store for the given identifier set.
    /// Maps `StoreKit.Product` into a provider-neutral shape so the bridge
    /// surface is fully fake-able (you cannot construct a `StoreKit.Product`
    /// in unit tests).
    func products(for ids: Set<String>) async throws -> [BridgeProduct]

    /// Snapshot of currently-entitled non-consumable / subscription products.
    /// Equivalent to iterating `Transaction.currentEntitlements`.
    func currentEntitlements() async -> Set<String>

    /// Trigger Apple's payment sheet for the given product. Returns a
    /// bridge-level outcome enum; live impl maps `Product.PurchaseResult`,
    /// fake supplies scripted values.
    func purchase(productId: String) async throws -> BridgePurchaseOutcome

    /// Force-sync the receipt with the App Store (Restore Purchases).
    func sync() async throws

    /// Long-lived stream of `Transaction.updates` (refunds, family-share,
    /// Ask-to-Buy approvals). Caller iterates for the app's lifetime.
    func transactionUpdates() -> AsyncStream<BridgeTransactionEvent>
}

// MARK: - BridgeProduct
//
// Fake-able snapshot of `StoreKit.Product`. The live bridge fills this from
// the real `Product`; `IAPProductMapper` then converts to `IAPProduct`.

internal struct BridgeProduct: Sendable, Equatable {
    let id: String
    let displayName: String
    let displayPrice: String

    init(id: String, displayName: String, displayPrice: String) {
        self.id = id
        self.displayName = displayName
        self.displayPrice = displayPrice
    }
}

// MARK: - BridgePurchaseOutcome
//
// Mirrors `Product.PurchaseResult` cases plus a `.failed` for thrown errors
// that the live impl catches and re-shapes (so the `IAPClient.purchase`
// surface can return `.failed(reason:)` rather than `throw`).
//
// `.success` carries the verified product ID; failure carries a reason
// string. `.unverified` is treated as `.failed` upstream — we never grant
// an entitlement on an unverified transaction.

internal enum BridgePurchaseOutcome: Sendable, Equatable {
    case success(productId: String)
    case userCancelled
    case pending
    case failed(reason: String)
}

// MARK: - BridgeTransactionEvent
//
// Compressed form of a verified `Transaction` from `Transaction.updates`.
// Live bridge inspects `revocationDate` to decide `.purchased` vs `.revoked`;
// fake emits these directly. Unverified entries are dropped at the bridge.

internal enum BridgeTransactionEvent: Sendable, Equatable {
    case purchased(productId: String)
    case revoked(productId: String)
}
