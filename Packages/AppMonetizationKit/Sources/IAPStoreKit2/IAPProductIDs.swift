// MARK: - IAPProductIDs
//
// Sudoku App Store Connect product identifiers. Test-only fixture: the
// production composition root (`AppComposition.Live`) now passes IDs into
// `LiveStoreKit2IAPClient` as data, so the package can serve a second app
// (Minesweeper) without baking Sudoku IDs into the production binary path.
// In-package tests still reference these constants as the canonical value.

internal enum IAPProductIDs {
    /// Non-consumable "Remove Ads" entitlement. See docs/v1/design.md §How.IAP.
    static let removeAds: String = "com.wei18.sudoku.iap.remove_ads"

    /// All product IDs known to the Sudoku catalog. Test fixture only —
    /// production passes its own set via `LiveStoreKit2IAPClient.init`.
    static let all: Set<String> = [
        removeAds,
    ]
}
