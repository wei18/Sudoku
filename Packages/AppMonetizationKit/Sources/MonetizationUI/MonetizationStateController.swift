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
internal import StoreKit
internal import SwiftUI

/// Stable identifier for the Remove Ads non-consumable. Mirrors
/// `IAPStoreKit2.IAPProductIDs.removeAds` (kept duplicated rather than
/// re-exported because that constant is `internal` to IAPStoreKit2 — the
/// App Store Connect product ID is the shared contract).
///
/// Retained as Sudoku's default after MS Phase 3 landed (2026-06-03) —
/// `MonetizationStateController.init` now takes a `productId:` param
/// defaulting to this constant so Sudoku call sites stay byte-identical
/// while Minesweeper passes `minesweeperRemoveAdsProductId`.
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
    /// ASC product ID this controller drives. Defaults to Sudoku's
    /// `removeAdsProductId` so existing call sites stay byte-identical.
    /// Minesweeper's composition root passes
    /// `com.wei18.minesweeper.iap.remove_ads` instead — see
    /// MinesweeperAppComposition.Live.
    @ObservationIgnored
    private let productId: String

    public init(
        iapClient: any IAPClient,
        stateStore: any AdGateStateStore,
        adGate: AdGate,
        toastController: ToastController? = nil,
        initialPurchased: Bool = false,
        productId: String = removeAdsProductId
    ) {
        self.iapClient = iapClient
        self.stateStore = stateStore
        self.adGate = adGate
        self.toastController = toastController
        self.hasPurchasedRemoveAds = initialPurchased
        self.productId = productId
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
        // try?: graceful local-fallback semantics — when the state store
        // throws (CloudKit unreachable / first launch), the controller
        // keeps the `initialPurchased` default already set in init. M10
        // (issue #67): the underlying CloudKit failure is reported by
        // `AdGate(onPersistenceError:)` wired in `AppComposition.live`
        // (see Live.swift), so this layer doesn't double-report. The
        // AdMob banner gate honours the false default and the toast on
        // an actual purchase attempt surfaces failure to the user.
        if let loaded = try? await stateStore.loadState() {
            hasPurchasedRemoveAds = loaded.hasPurchasedRemoveAds
        }
        // try?: same rationale — IAP catalog desync is reported by
        // `LiveStoreKit2IAPClient(onCatalogDesync:)` in Live.swift; an
        // empty `availableProducts` here is a benign UI state (Settings
        // shows the fallback `"$2.99"` placeholder per the M3 polish doc).
        if let products = try? await iapClient.availableProducts() {
            availableProducts = products
            // Stay in sync with the App Store side too — a restored entitlement
            // that hasn't yet been written back to MonetizationState shows up
            // here as `isPurchased = true` and should flip the local flag.
            if let removeAds = products.first(where: { $0.id == productId }),
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
        case .purchased(let eventProductId):
            guard eventProductId == productId else { return }
            await markPurchased()
            latestMessage = .adsRemoved
            toastController?.show(Toast(style: .success, message: "Ads removed"))
        case .revoked(let eventProductId):
            guard eventProductId == productId else { return }
            hasPurchasedRemoveAds = false
            latestMessage = .failure(reason: "Purchase revoked")
            toastController?.show(Toast(style: .failure, message: "Purchase revoked"))
        }
    }

    /// Resolved Remove Ads display price. Falls back to `"$2.99"` (the
    /// spec'd default) when the App Store lookup has not yet completed.
    public var removeAdsDisplayPrice: String {
        availableProducts.first(where: { $0.id == productId })?.displayPrice ?? "$2.99"
    }

    /// Tap handler for "Remove Ads" buttons (Settings row + HomeView 5th card).
    public func purchaseRemoveAds() async {
        guard !purchaseInFlight else { return }
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        do {
            let result = try await iapClient.purchase(productId)
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
            // StoreKit user-cancellation (e.g. App Store password sheet dismissed)
            // is silent — mirrors the in-band `.userCancelled` case above.
            if case .userCancelled = error as? StoreKitError {
                latestMessage = nil
            } else {
                let reason = "Purchase failed"
                latestMessage = .failure(reason: reason)
                toastController?.show(Toast(style: .failure, message: reason))
            }
        }
    }

    /// Tap handler for the "Restore Purchases" button.
    public func restorePurchases() async {
        guard !restoreInFlight else { return }
        restoreInFlight = true
        defer { restoreInFlight = false }
        do {
            let restored = try await iapClient.restorePurchases()
            if restored.contains(where: { $0.id == productId && $0.isPurchased }) {
                await markPurchased()
            }
            availableProducts = restored
            latestMessage = .restored
            toastController?.show(Toast(style: .success, message: "Purchases restored"))
        } catch {
            // StoreKit user-cancellation (e.g. App Store sign-in sheet dismissed
            // during restore) is silent — no toast, no latestMessage update.
            if case .userCancelled = error as? StoreKitError {
                latestMessage = nil
            } else {
                let reason = "Restore failed"
                latestMessage = .failure(reason: reason)
                toastController?.show(Toast(style: .failure, message: reason))
            }
        }
    }

    private func markPurchased() async {
        hasPurchasedRemoveAds = true
        await adGate.recordPurchase()
    }
}
