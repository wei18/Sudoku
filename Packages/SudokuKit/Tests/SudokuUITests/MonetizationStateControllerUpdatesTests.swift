// MonetizationStateControllerUpdatesTests — v2.4.5.
//
// Behavior under test:
//   - After `bootstrap()`, the controller subscribes to
//     `iapClient.purchaseUpdates()` and reacts to out-of-band events.
//   - `.revoked` flips `hasPurchasedRemoveAds` back to false + pushes a
//     failure toast + failure latestMessage.
//   - `.purchased` (from an external grant — Ask to Buy approval) flips
//     the flag to true + pushes a success toast.
//   - Toasts also fire on the in-band `purchaseRemoveAds()` / `restorePurchases()`
//     paths when a `ToastController` is wired in.

import Foundation
import Testing

import MonetizationCore
import MonetizationTesting
import Persistence
@testable import SudokuUI

@MainActor
@Suite("MonetizationStateController — purchaseUpdates() + toasts")
struct MonetizationStateControllerUpdatesTests {

    private func make(
        purchased: Bool = false,
        products: [IAPProduct] = []
    ) async -> (MonetizationStateController, FakeIAPClient, ToastController) {
        let store = FakeAdGateStateStore(
            initial: AdGateState(
                firstLaunchAt: Date(timeIntervalSince1970: 0),
                hasPurchasedRemoveAds: purchased
            )
        )
        let iap = FakeIAPClient()
        await iap.setProducts(products)
        let gate = AdGate(store: store)
        let toast = ToastController()
        let controller = MonetizationStateController(
            iapClient: iap,
            stateStore: store,
            adGate: gate,
            toastController: toast
        )
        return (controller, iap, toast)
    }

    /// Wait up to `timeout` for `predicate` to become true. Yields the main
    /// loop between checks so the controller's update-subscriber Task can
    /// process the emitted event.
    private func waitFor(
        timeout: Duration = .milliseconds(500),
        _ predicate: @MainActor () -> Bool
    ) async {
        let start = ContinuousClock.now
        while ContinuousClock.now - start < timeout {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func revokedEvent_flipsFlagFalse_andPushesFailureToast() async {
        let (controller, iap, toast) = await make(purchased: true)
        await controller.bootstrap()
        // Fix B (RCA 2026-05-25): listener opt-in is explicit in tests,
        // matched by `finishUpdates()` so the for-await Task doesn't
        // outlive the suite instance and starve the @MainActor.
        controller.startListeningForLifetimeOfApp()
        defer { Task { await iap.finishUpdates() } }
        #expect(controller.hasPurchasedRemoveAds == true)

        await iap.emit(.revoked(productId: removeAdsProductId))

        await waitFor { controller.hasPurchasedRemoveAds == false }
        // Toast is populated by a separate MainActor hop after the flag flip —
        // poll for it before asserting (fix #187). Without this, the assertion
        // races the toast.show() Task and fails intermittently under parallel
        // test load (XCC scheduling, surfaced once the scheme's testAction
        // started exercising this suite in PR #185).
        await waitFor { toast.current != nil }
        #expect(controller.hasPurchasedRemoveAds == false)
        #expect(controller.latestMessage == .failure(reason: "Purchase revoked"))
        #expect(toast.current?.style == .failure)
        #expect(toast.current?.message == "Purchase revoked")
    }

    @Test func purchasedEvent_flipsFlagTrue_andPushesSuccessToast() async {
        let (controller, iap, toast) = await make()
        await controller.bootstrap()
        controller.startListeningForLifetimeOfApp()
        defer { Task { await iap.finishUpdates() } }
        #expect(controller.hasPurchasedRemoveAds == false)

        await iap.emit(.purchased(productId: removeAdsProductId))

        await waitFor { controller.hasPurchasedRemoveAds == true }
        // See revokedEvent test for the propagation-race rationale (#187).
        await waitFor { toast.current != nil }
        #expect(controller.hasPurchasedRemoveAds == true)
        #expect(controller.latestMessage == .adsRemoved)
        #expect(toast.current?.style == .success)
        #expect(toast.current?.message == "Ads removed")
    }

    @Test func purchasedEvent_forUnrelatedProductId_ignored() async {
        let (controller, iap, toast) = await make()
        await controller.bootstrap()
        controller.startListeningForLifetimeOfApp()
        defer { Task { await iap.finishUpdates() } }

        await iap.emit(.purchased(productId: "com.wei18.sudoku.iap.other"))

        // Give the subscriber a chance to receive the event.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(controller.hasPurchasedRemoveAds == false)
        #expect(toast.current == nil)
    }

    @Test func purchaseTap_pushesSuccessToast_whenWired() async {
        let (controller, iap, toast) = await make(
            products: [IAPProduct(id: removeAdsProductId, displayName: "Remove Ads", displayPrice: "$2.99", isPurchased: false)]
        )
        let product = IAPProduct(id: removeAdsProductId, displayName: "Remove Ads", displayPrice: "$2.99", isPurchased: true)
        await iap.setPurchaseResult(for: removeAdsProductId, result: .success(product))
        await controller.bootstrap()

        await controller.purchaseRemoveAds()

        #expect(toast.current?.style == .success)
        #expect(toast.current?.message == "Ads removed")
    }

    @Test func purchaseTap_pushesFailureToast_onFailure() async {
        let (controller, iap, toast) = await make()
        await iap.setPurchaseResult(for: removeAdsProductId, result: .failed(reason: "card declined"))
        await controller.bootstrap()

        await controller.purchaseRemoveAds()

        #expect(toast.current?.style == .failure)
        #expect(toast.current?.message == "card declined")
    }

    @Test func restoreTap_pushesSuccessToast_whenWired() async {
        let (controller, _, toast) = await make(
            products: [IAPProduct(id: removeAdsProductId, displayName: "Remove Ads", displayPrice: "$2.99", isPurchased: false)]
        )

        await controller.restorePurchases()

        #expect(toast.current?.style == .success)
        #expect(toast.current?.message == "Purchases restored")
    }
}
