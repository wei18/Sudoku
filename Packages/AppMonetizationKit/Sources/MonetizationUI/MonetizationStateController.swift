// MonetizationStateController — v2.3.6 shared @Observable view-model state for
// Settings + HomeView surfaces that drive (or react to) Remove Ads.
//
// State owned here:
//   - `hasPurchasedRemoveAds: Bool` — read from the persisted MonetizationState
//     on `bootstrap()`; flipped to `true` after a successful purchase or restore.
//   - `purchaseInFlight: Bool` / `restoreInFlight: Bool` — drive the spinner
//     swap in Settings + HomeView's Remove Ads card while the async call runs.
//     Both are computed projections of the private `flowState:
//     PurchaseFlowState` enum (#881) — a single source of truth so
//     "purchasing and restoring at once" and "failed looks like never
//     attempted" (#874 F-6/F-7/F-8) are unrepresentable by construction.
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
// Lifetime: one instance is constructed in SudokuAppComposition's preview/tests/live
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

    /// Closed representation of the purchase/restore flow's UI state (#881,
    /// closing #874 F-6/F-7/F-8). `purchaseInFlight` and `restoreInFlight`
    /// used to be two independent stored `Bool`s with independent guards, so
    /// nothing stopped both being `true` at once (F-6) and a failed purchase
    /// left no state distinguishable from "never attempted" (F-7). Both
    /// flags below are now computed projections of this single stored enum,
    /// so "purchasing and restoring at once" is unrepresentable by
    /// construction rather than merely guarded against.
    ///
    /// Kept module-`internal`, not `public` — the public `purchaseInFlight` /
    /// `restoreInFlight` / `latestMessage` surface is unchanged, so existing
    /// call sites (every test that reads those bools) don't need to change.
    /// `flowState` itself is read directly only by `RemoveAdsRow` (same
    /// module) for the failed-purchase treatment, and by this module's own
    /// tests.
    enum PurchaseFlowState: Sendable, Equatable {
        case idle
        case purchasing
        case restoring
        /// The most recent purchase attempt failed (or is pending external
        /// approval). Distinct from `.idle` so `RemoveAdsRow` can render a
        /// "last attempt failed" treatment instead of looking identical to
        /// never-attempted (#874 F-7). Cleared by the next purchase attempt
        /// (success or failure both replace it) or by a restore completing.
        case purchaseFailed(reason: String)

        var isInFlight: Bool {
            switch self {
            case .purchasing, .restoring: true
            case .idle, .purchaseFailed: false
            }
        }
    }

    public private(set) var hasPurchasedRemoveAds: Bool
    public private(set) var availableProducts: [IAPProduct] = []
    /// In-memory only — accepted scope (#894): the "Last attempt failed"
    /// indicator does not persist across relaunch, unlike `hasPurchasedRemoveAds`.
    private(set) var flowState: PurchaseFlowState = .idle
    public private(set) var latestMessage: Message?

    /// Computed projection of `flowState` — unchanged public shape (#881).
    public var purchaseInFlight: Bool {
        if case .purchasing = flowState { return true }
        return false
    }

    /// Computed projection of `flowState` — unchanged public shape (#881).
    public var restoreInFlight: Bool {
        if case .restoring = flowState { return true }
        return false
    }

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
    /// `purchaseUpdates()` listener. Production (`SudokuAppComposition.live`)
    /// calls `startListeningForLifetimeOfApp()` once at boot, immediately
    /// after `bootstrap()`. Tests that need the listener opt in
    /// explicitly + tear down via `FakeIAPClient.finishUpdates()`.
    public func bootstrap() async {
        // try?: graceful local-fallback semantics — when the state store
        // throws (CloudKit unreachable / first launch), the controller
        // keeps the `initialPurchased` default already set in init. M10
        // (issue #67): the underlying CloudKit failure is reported by
        // `AdGate(onPersistenceError:)` wired in `SudokuAppComposition.live`
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
            // #901: raw literal was the toast's VISIBLE text (ToastView renders
            // `toast.message` directly) — route through the catalog. Reuses the
            // sentence-case "Ads removed" key #895 added for AdsRemovedRow's a11y label.
            toastController?.show(Toast(style: .success, message: String(localized: "Ads removed", bundle: .main)))
            clearStalePurchaseFailure()
        case .revoked(let eventProductId):
            guard eventProductId == productId else { return }
            hasPurchasedRemoveAds = false
            // #901: localize the visible toast + a11y `latestMessage` reason.
            let reason = String(localized: "Purchase revoked", bundle: .main)
            latestMessage = .failure(reason: reason)
            toastController?.show(Toast(style: .failure, message: reason))
            // #894: an out-of-band revoke is unrelated to any earlier
            // purchase-attempt failure — clear it so RemoveAdsRow re-mounts
            // fresh instead of blaming a stale "Last attempt failed".
            clearStalePurchaseFailure()
        }
    }

    /// Drops a stale `.purchaseFailed` left over from an earlier attempt when
    /// an out-of-band entitlement-changing event settles the question some
    /// other way (#894). No-op for `.idle` / in-flight states — this only
    /// ever narrows `.purchaseFailed` to `.idle`.
    private func clearStalePurchaseFailure() {
        if case .purchaseFailed = flowState {
            flowState = .idle
        }
    }

    /// Resolved Remove Ads display price. Falls back to `"$2.99"` (the
    /// spec'd default) when the App Store lookup has not yet completed.
    public var removeAdsDisplayPrice: String {
        availableProducts.first(where: { $0.id == productId })?.displayPrice ?? "$2.99"
    }

    /// Tap handler for "Remove Ads" buttons (Settings row + HomeView 5th card).
    public func purchaseRemoveAds() async {
        guard !flowState.isInFlight else { return }
        flowState = .purchasing
        do {
            let result = try await iapClient.purchase(productId)
            switch result {
            case .success:
                await markPurchased()
                latestMessage = .adsRemoved
                // #901: localize the visible toast (reuses #895's "Ads removed" key).
                toastController?.show(Toast(style: .success, message: String(localized: "Ads removed", bundle: .main)))
                flowState = .idle
            case .userCancelled:
                latestMessage = nil
                flowState = .idle
            case .pending:
                let reason = String(localized: "Purchase pending approval", bundle: .main)
                latestMessage = .failure(reason: reason)
                toastController?.show(Toast(style: .failure, message: reason))
                flowState = .purchaseFailed(reason: reason)
            case .failed(let reason):
                latestMessage = .failure(reason: reason)
                toastController?.show(Toast(style: .failure, message: reason))
                flowState = .purchaseFailed(reason: reason)
            }
        } catch {
            // StoreKit user-cancellation (e.g. App Store password sheet dismissed)
            // is silent — mirrors the in-band `.userCancelled` case above.
            if case .userCancelled = error as? StoreKitError {
                latestMessage = nil
                flowState = .idle
            } else {
                let reason = String(localized: "Purchase failed", bundle: .main)
                latestMessage = .failure(reason: reason)
                toastController?.show(Toast(style: .failure, message: reason))
                flowState = .purchaseFailed(reason: reason)
            }
        }
    }

    /// Tap handler for the "Restore Purchases" button.
    public func restorePurchases() async {
        guard !flowState.isInFlight else { return }
        // Only `.idle` or `.purchaseFailed` can reach here (the guard above
        // rules out `.purchasing` / `.restoring`) — saved so a restore that
        // doesn't resolve the entitlement question can put it back (#894).
        let previousFlowState = flowState
        flowState = .restoring
        do {
            let restored = try await iapClient.restorePurchases()
            if restored.contains(where: { $0.id == productId && $0.isPurchased }) {
                await markPurchased()
            }
            availableProducts = restored
            latestMessage = .restored
            // #901: localize the visible toast.
            toastController?.show(Toast(style: .success, message: String(localized: "Purchases restored", bundle: .main)))
            // Restore succeeding resolves the flow — it also clears a stale
            // `.purchaseFailed` from an earlier purchase attempt, since the
            // entitlement question is now settled.
            flowState = .idle
        } catch {
            // StoreKit user-cancellation (e.g. App Store sign-in sheet dismissed
            // during restore) is silent — no toast, no latestMessage update.
            if case .userCancelled = error as? StoreKitError {
                latestMessage = nil
            } else {
                let reason = String(localized: "Restore failed", bundle: .main)
                latestMessage = .failure(reason: reason)
                toastController?.show(Toast(style: .failure, message: reason))
            }
            // #894: a restore that fails (or is cancelled) doesn't resolve
            // the entitlement question, so it shouldn't erase evidence of an
            // earlier failed purchase — restore whatever flow state preceded
            // this attempt instead of unconditionally clearing to `.idle`.
            // Smaller semantic chosen deliberately: the failure is still
            // toasted (existing behavior), but restore failure does not get
            // its own `PurchaseFlowState` case — that would double the enum's
            // failure surface for a case RemoveAdsRow doesn't need to tell
            // apart from a failed purchase.
            flowState = previousFlowState
        }
    }

    private func markPurchased() async {
        hasPurchasedRemoveAds = true
        await adGate.recordPurchase()
    }
}
