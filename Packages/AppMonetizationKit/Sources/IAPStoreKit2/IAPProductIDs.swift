// MARK: - IAPProductIDs
//
// Single source of truth for App Store Connect product identifiers consumed
// by `LiveStoreKit2IAPClient`. Kept `internal` — callers ask for products by
// semantic role (e.g. via `IAPClient.availableProducts()`), not by raw ID.
//
// When a new product ships in ASC, add the constant here and surface it
// through the `knownProductIds` set below so `Product.products(for:)` picks
// it up at fetch time.

internal enum IAPProductIDs {
    /// Non-consumable "Remove Ads" entitlement. See docs/v1/design.md §How.IAP.
    static let removeAds: String = "com.wei18.sudoku.iap.remove_ads"

    /// All product IDs that `LiveStoreKit2IAPClient` will fetch from the
    /// App Store on `availableProducts()`. Ordered alphabetically for
    /// diff stability.
    static let all: Set<String> = [
        removeAds,
    ]
}
