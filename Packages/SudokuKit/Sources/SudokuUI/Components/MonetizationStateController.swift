// MonetizationStateController — v2.3.6 shared @Observable view-model state for
// Settings + HomeView surfaces that drive (or react to) Remove Ads.
//
// State owned here:
//   - `hasPurchasedRemoveAds: Bool` — read from the persisted MonetizationState
//     on `bootstrap()`; flipped to `true` after a successful purchase or restore.
//   - `purchaseInFlight: Bool` / `restoreInFlight: Bool` — drive the spinner
//     swap in Settings + HomeView's Remove Ads card while the async call runs.
//   - `availableProducts: [IAPProduct]` — cached on bootstrap so the Settings
//     CTA can show the locale-formatted price (`"$2.99"` / `"NT$89"` etc.) the
//     App Store returns; falls back to `"$2.99"` if the lookup fails.
//   - `latestMessage: Message?` — surfaces success / failure inline (no toast
//     infra exists in SudokuUI yet — see impl-notes §未決).
//
// Lifetime: one instance is constructed in AppComposition's preview/tests/live
// path and re-used across HomeView and Settings so both surfaces observe the
// same `hasPurchasedRemoveAds` flip after a purchase.

public import Foundation
public import MonetizationCore
internal import SwiftUI

/// Stable identifier for the Remove Ads non-consumable. Mirrors
/// `IAPStoreKit2.IAPProductIDs.removeAds` (kept duplicated rather than
/// re-exported because that constant is `internal` to IAPStoreKit2 — the
/// App Store Connect product ID is the shared contract).
public let removeAdsProductId: String = "com.wei18.sudoku.iap.remove_ads"

@MainActor
@Observable
public final class MonetizationStateController {

    public enum Message: Sendable, Equatable {
        case adsRemoved
        case restored
        case failure(reason: String)
    }

    public private(set) var hasPurchasedRemoveAds: Bool
    public private(set) var availableProducts: [IAPProduct] = []
    public private(set) var purchaseInFlight: Bool = false
    public private(set) var restoreInFlight: Bool = false
    public private(set) var latestMessage: Message?

    @ObservationIgnored
    private let iapClient: any IAPClient
    @ObservationIgnored
    private let stateStore: any AdGateStateStore
    @ObservationIgnored
    private let adGate: AdGate

    public init(
        iapClient: any IAPClient,
        stateStore: any AdGateStateStore,
        adGate: AdGate,
        initialPurchased: Bool = false
    ) {
        self.iapClient = iapClient
        self.stateStore = stateStore
        self.adGate = adGate
        self.hasPurchasedRemoveAds = initialPurchased
    }

    /// One-shot read of persisted state + available products. Safe to call
    /// repeatedly (Settings and HomeView both invoke it from `.task`); the
    /// store + IAPClient are responsible for their own caching.
    public func bootstrap() async {
        if let loaded = try? await stateStore.loadState() {
            hasPurchasedRemoveAds = loaded.hasPurchasedRemoveAds
        }
        if let products = try? await iapClient.availableProducts() {
            availableProducts = products
            // Stay in sync with the App Store side too — a restored entitlement
            // that hasn't yet been written back to MonetizationState shows up
            // here as `isPurchased = true` and should flip the local flag.
            if let removeAds = products.first(where: { $0.id == removeAdsProductId }),
               removeAds.isPurchased {
                hasPurchasedRemoveAds = true
            }
        }
    }

    /// Resolved Remove Ads display price. Falls back to `"$2.99"` (the
    /// spec'd default) when the App Store lookup has not yet completed.
    public var removeAdsDisplayPrice: String {
        availableProducts.first(where: { $0.id == removeAdsProductId })?.displayPrice ?? "$2.99"
    }

    /// Tap handler for "Remove Ads" buttons (Settings row + HomeView 5th card).
    public func purchaseRemoveAds() async {
        guard !purchaseInFlight else { return }
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        do {
            let result = try await iapClient.purchase(removeAdsProductId)
            switch result {
            case .success:
                await markPurchased()
                latestMessage = .adsRemoved
            case .userCancelled:
                latestMessage = nil
            case .pending:
                latestMessage = .failure(reason: "Purchase pending approval")
            case .failed(let reason):
                latestMessage = .failure(reason: reason)
            }
        } catch {
            latestMessage = .failure(reason: String(describing: error))
        }
    }

    /// Tap handler for the "Restore Purchases" button.
    public func restorePurchases() async {
        guard !restoreInFlight else { return }
        restoreInFlight = true
        defer { restoreInFlight = false }
        do {
            let restored = try await iapClient.restorePurchases()
            if restored.contains(where: { $0.id == removeAdsProductId && $0.isPurchased }) {
                await markPurchased()
            }
            availableProducts = restored
            latestMessage = .restored
        } catch {
            latestMessage = .failure(reason: String(describing: error))
        }
    }

    private func markPurchased() async {
        hasPurchasedRemoveAds = true
        await adGate.recordPurchase()
    }
}
