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
//   - `latestMessage: Message?` — a11y / VoiceOver source of truth for the
//     Settings inline `Label` row. The visual surface is the `ToastController`
//     (v2.4.5); `latestMessage` stays because VoiceOver does not reliably
//     announce a transient overlay toast.
//
// v2.4.5 additions:
//   - Optional `ToastController` injection. When present, purchase / restore
//     results push a toast in addition to setting `latestMessage`.
//   - `startListeningForLifetimeOfApp()` subscribes to
//     `iapClient.purchaseUpdates()` for the app's lifetime, handling
//     out-of-band events (refunds, family-share revocations). Called
//     explicitly at app boot (alongside `bootstrap()`); cancelled on
//     `deinit`.
//
// Fix B (RCA 2026-05-25): the listener subscription is split out of
// `bootstrap()` so swift-testing suites that only need the one-shot read
// don't leak a long-lived `for await` Task on the shared `@MainActor`,
// which deadlocks the full test suite. Tests that DO exercise the
// listener call `startListeningForLifetimeOfApp()` explicitly + tear
// down via `FakeIAPClient.finishUpdates()`.
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
    @ObservationIgnored
    private let toastController: ToastController?
    @ObservationIgnored
    private var updatesTask: Task<Void, Never>?

    public init(
        iapClient: any IAPClient,
        stateStore: any AdGateStateStore,
        adGate: AdGate,
        toastController: ToastController? = nil,
        initialPurchased: Bool = false
    ) {
        self.iapClient = iapClient
        self.stateStore = stateStore
        self.adGate = adGate
        self.toastController = toastController
        self.hasPurchasedRemoveAds = initialPurchased
    }

    deinit {
        updatesTask?.cancel()
    }

    /// One-shot read of persisted state + available products. Safe to call
    /// repeatedly (Settings and HomeView both invoke it from `.task`); the
    /// store + IAPClient are responsible for their own caching.
    ///
    /// Fix B (RCA 2026-05-25): this method NO LONGER starts the
    /// `purchaseUpdates()` listener. Production (`AppComposition.live`)
    /// calls `startListeningForLifetimeOfApp()` once at boot, immediately
    /// after `bootstrap()`. Tests that need the listener opt in
    /// explicitly + tear down via `FakeIAPClient.finishUpdates()`.
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

    /// Long-running subscriber for out-of-band purchase events (refunds,
    /// family-share revocations, parental-approval grants). Call ONCE at
    /// app boot from the composition root; tests opt in explicitly. Safe
    /// to call multiple times — any previous task is cancelled first.
    public func startListeningForLifetimeOfApp() {
        updatesTask?.cancel()
        let stream = iapClient.purchaseUpdates()
        updatesTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    private func handle(_ event: IAPPurchaseEvent) async {
        switch event {
        case .purchased(let productId):
            guard productId == removeAdsProductId else { return }
            await markPurchased()
            latestMessage = .adsRemoved
            toastController?.show(Toast(style: .success, message: "Ads removed"))
        case .revoked(let productId):
            guard productId == removeAdsProductId else { return }
            hasPurchasedRemoveAds = false
            latestMessage = .failure(reason: "Purchase revoked")
            toastController?.show(Toast(style: .failure, message: "Purchase revoked"))
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
                toastController?.show(Toast(style: .success, message: "Ads removed"))
            case .userCancelled:
                latestMessage = nil
            case .pending:
                let reason = "Purchase pending approval"
                latestMessage = .failure(reason: reason)
                toastController?.show(Toast(style: .failure, message: reason))
            case .failed(let reason):
                latestMessage = .failure(reason: reason)
                toastController?.show(Toast(style: .failure, message: reason))
            }
        } catch {
            let reason = String(describing: error)
            latestMessage = .failure(reason: reason)
            toastController?.show(Toast(style: .failure, message: reason))
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
            toastController?.show(Toast(style: .success, message: "Purchases restored"))
        } catch {
            let reason = String(describing: error)
            latestMessage = .failure(reason: reason)
            toastController?.show(Toast(style: .failure, message: reason))
        }
    }

    private func markPurchased() async {
        hasPurchasedRemoveAds = true
        await adGate.recordPurchase()
    }
}
