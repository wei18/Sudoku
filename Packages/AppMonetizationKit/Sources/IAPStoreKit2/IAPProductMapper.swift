internal import MonetizationCore

// MARK: - IAPProductMapper
//
// Pure function from a `BridgeProduct` snapshot + entitlement flag to the
// provider-neutral `IAPProduct`. Kept independent of `StoreKit.Product` so
// it stays testable without any Apple-framework instances.

internal struct IAPProductMapper {
    static func map(_ product: BridgeProduct, isPurchased: Bool) -> IAPProduct {
        IAPProduct(
            id: product.id,
            displayName: product.displayName,
            displayPrice: product.displayPrice,
            isPurchased: isPurchased
        )
    }
}
