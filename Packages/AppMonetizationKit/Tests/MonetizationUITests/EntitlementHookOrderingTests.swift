// EntitlementHookOrderingTests — every entitlement path updates its UI (toast,
// message, flow state) before awaiting `onEntitlementChanged`, whose banner
// disposal must not delay them (#1058 2c.1, MINOR-4).
//
// Mutation target: move `await onEntitlementChanged?()` back into
// `markPurchased()`, ahead of the callers' UI updates.

import Foundation
import Testing

import MonetizationCore
import MonetizationTesting
@testable import MonetizationUI

@MainActor
@Suite("MonetizationStateController — UI before the entitlement hook (#1058)", .timeLimit(.minutes(1)))
struct EntitlementHookOrderingTests {

    /// The hook opens `entered`, then waits for `release` without observing
    /// cancellation, so the test inspects the controller while it is held.
    private final class HeldHook: Sendable {
        let entered = ReadinessLatch()
        let release = ReadinessLatch()
    }

    private func makeController(
        iap: FakeIAPClient,
        hook: HeldHook,
        toasts: ToastController
    ) -> MonetizationStateController {
        let store = FakeAdGateStateStore(initial: AdGateState(firstLaunchAt: Date(timeIntervalSince1970: 0)))
        return MonetizationStateController(
            iapClient: iap,
            stateStore: store,
            adGate: AdGate(store: store),
            toastController: toasts,
            onEntitlementChanged: {
                hook.entered.open()
                while !hook.release.isOpen {
                    try? await Task.sleep(for: .milliseconds(5))
                }
            }
        )
    }

    @Test("purchase: toast, message and .idle are set before the hook runs")
    func purchaseUpdatesUIBeforeHook() async throws {
        let iap = FakeIAPClient()
        let product = IAPProduct(id: removeAdsProductId, displayName: "Remove Ads", displayPrice: "$0.99", isPurchased: true)
        await iap.setPurchaseResult(for: removeAdsProductId, result: .success(product))
        let hook = HeldHook()
        let toasts = ToastController()
        let controller = makeController(iap: iap, hook: hook, toasts: toasts)

        let purchasing = Task { await controller.purchaseRemoveAds() }
        try await hook.entered.wait()

        #expect(controller.flowState == .idle)
        #expect(controller.latestMessage == .adsRemoved)
        #expect(toasts.current?.style == .success)
        hook.release.open()
        await purchasing.value
    }

    @Test("restore: toast, message and .idle are set before the hook runs")
    func restoreUpdatesUIBeforeHook() async throws {
        let iap = FakeIAPClient()
        await iap.setProducts([
            IAPProduct(id: removeAdsProductId, displayName: "Remove Ads", displayPrice: "$0.99", isPurchased: false),
        ])
        let hook = HeldHook()
        let toasts = ToastController()
        let controller = makeController(iap: iap, hook: hook, toasts: toasts)

        let restoring = Task { await controller.restorePurchases() }
        try await hook.entered.wait()

        #expect(controller.flowState == .idle)
        #expect(controller.latestMessage == .restored)
        #expect(toasts.current?.style == .success)
        hook.release.open()
        await restoring.value
    }

    @Test("purchase updates: toast and message are set before the hook runs")
    func updatesListenerUpdatesUIBeforeHook() async throws {
        let iap = FakeIAPClient()
        let hook = HeldHook()
        let toasts = ToastController()
        let controller = makeController(iap: iap, hook: hook, toasts: toasts)

        controller.startListeningForLifetimeOfApp()
        await iap.emit(.purchased(productId: removeAdsProductId))
        try await hook.entered.wait()

        #expect(controller.latestMessage == .adsRemoved)
        #expect(toasts.current?.style == .success)
        hook.release.open()
        await iap.finishUpdates()
    }
}
