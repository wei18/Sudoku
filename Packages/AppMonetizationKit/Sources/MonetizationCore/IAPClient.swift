// MARK: - IAPClient
//
// Provider-neutral surface for in-app purchases. Concrete implementation
// (IAPStoreKit2.LiveStoreKit2IAPClient) wraps Apple's StoreKit 2 and stays
// behind this protocol so MonetizationCore stays Apple-framework-free.

public protocol IAPClient: Sendable {
    /// Products configured in App Store Connect that this client can sell.
    func availableProducts() async throws -> [IAPProduct]

    /// Trigger Apple's native payment sheet for the given product. Result
    /// surfaces via the return value AND `purchaseUpdates()` (the same
    /// successful purchase appears in both — callers should treat
    /// `purchaseUpdates` as the source of truth for entitlement state).
    func purchase(_ productId: String) async throws -> IAPPurchaseResult

    /// Re-sync past purchases from App Store. Used by Settings → Restore
    /// Purchases. Returns the previously-purchased products with
    /// `isPurchased = true`.
    func restorePurchases() async throws -> [IAPProduct]

    /// Long-lived stream of out-of-band purchase events: external transactions
    /// (parental approval), refunds, family-sharing changes. Subscribed at
    /// app launch and observed for the app's lifetime.
    func purchaseUpdates() -> AsyncStream<IAPPurchaseEvent>
}

// MARK: - IAPProduct

public struct IAPProduct: Sendable, Equatable {
    public let id: String
    public let displayName: String
    /// Already locale-formatted price string (e.g. "NT$89", "$2.99").
    public let displayPrice: String
    public let isPurchased: Bool

    public init(
        id: String,
        displayName: String,
        displayPrice: String,
        isPurchased: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.displayPrice = displayPrice
        self.isPurchased = isPurchased
    }
}

// MARK: - IAPPurchaseResult

public enum IAPPurchaseResult: Sendable, Equatable {
    case success(IAPProduct)
    case userCancelled
    /// Awaiting parental approval (Ask to Buy) or pending external payment.
    case pending
    case failed(reason: String)
}

// MARK: - IAPPurchaseEvent

public enum IAPPurchaseEvent: Sendable, Equatable {
    case purchased(productId: String)
    /// Refund granted by Apple Support OR family-share entitlement lost.
    case revoked(productId: String)
}
