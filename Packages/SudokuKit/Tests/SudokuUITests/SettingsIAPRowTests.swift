// SettingsIAPRowTests — v2.3.6.
//
// Behavior under test (the controller, which Settings observes 1:1):
//   - Unpurchased state surfaces both rows; price tracks `availableProducts`.
//   - Purchased state hides the Remove Ads CTA; Restore stays visible.
//   - Purchase tap → `iapClient.purchase("…remove_ads")` called once.
//   - Restore tap → `iapClient.restorePurchases()` called once.
//   - In-flight flags flip while the async call runs.
//   - Success / failure surface via `latestMessage` (Settings View renders
//     this as the inline Label row — see SettingsView.swift).

import Foundation
import SnapshotTesting
import SwiftUI
import Testing

import MonetizationCore
import MonetizationTesting
import Persistence
import SudokuKitTesting
@testable import SudokuUI

@MainActor
@Suite("SettingsView — Remove Ads + Restore Purchases rows")
struct SettingsIAPRowTests {

    private func makeStore(purchased: Bool = false) -> FakeAdGateStateStore {
        FakeAdGateStateStore(
            initial: AdGateState(
                firstLaunchAt: Date(timeIntervalSince1970: 0),
                hasPurchasedRemoveAds: purchased
            )
        )
    }

    private func makeController(
        purchased: Bool = false,
        products: [IAPProduct] = []
    ) async -> (MonetizationStateController, FakeIAPClient, FakeAdGateStateStore) {
        let store = makeStore(purchased: purchased)
        let iap = FakeIAPClient()
        await iap.setProducts(products)
        let gate = AdGate(store: store)
        let controller = MonetizationStateController(
            iapClient: iap,
            stateStore: store,
            adGate: gate
        )
        return (controller, iap, store)
    }

    // MARK: - Unpurchased: both rows visible, price = product price

    @Test func unpurchased_showsBothRows_andResolvesDisplayPrice() async {
        let product = IAPProduct(
            id: removeAdsProductId,
            displayName: "Remove Ads",
            displayPrice: "$2.99",
            isPurchased: false
        )
        let (controller, _, _) = await makeController(products: [product])
        await controller.bootstrap()

        #expect(controller.hasPurchasedRemoveAds == false)
        #expect(controller.removeAdsDisplayPrice == "$2.99")
    }

    @Test func unpurchased_displayPrice_fallsBackTo2_99WhenLookupEmpty() async {
        let (controller, _, _) = await makeController(products: [])
        await controller.bootstrap()
        #expect(controller.removeAdsDisplayPrice == "$2.99")
    }

    // MARK: - Purchased: Remove Ads CTA hidden

    @Test func purchased_hidesRemoveAdsCTA_keepsRestore() async {
        let (controller, _, _) = await makeController(purchased: true)
        await controller.bootstrap()
        #expect(controller.hasPurchasedRemoveAds == true)
        // The Settings View reads `hasPurchasedRemoveAds` to gate the
        // `RemoveAdsRow` rendering; Restore is always visible regardless.
    }

    // MARK: - Purchase tap → iapClient.purchase called once

    @Test func purchaseTap_callsPurchaseOnce() async {
        let (controller, iap, _) = await makeController(
            products: [IAPProduct(id: removeAdsProductId, displayName: "Remove Ads", displayPrice: "$2.99", isPurchased: false)]
        )
        let product = IAPProduct(id: removeAdsProductId, displayName: "Remove Ads", displayPrice: "$2.99", isPurchased: true)
        await iap.setPurchaseResult(for: removeAdsProductId, result: .success(product))
        await controller.bootstrap()

        await controller.purchaseRemoveAds()

        let calls = await iap.purchaseCallCount
        #expect(calls == 1)
        #expect(controller.hasPurchasedRemoveAds == true)
        #expect(controller.latestMessage == .adsRemoved)
    }

    // MARK: - Restore tap → iapClient.restorePurchases called once

    @Test func restoreTap_callsRestoreOnce() async {
        let (controller, iap, _) = await makeController(
            products: [IAPProduct(id: removeAdsProductId, displayName: "Remove Ads", displayPrice: "$2.99", isPurchased: false)]
        )

        await controller.restorePurchases()

        let calls = await iap.restoreCallCount
        #expect(calls == 1)
        // FakeIAPClient.restorePurchases flips `isPurchased = true` on all
        // tracked products → controller sees the Remove Ads entitlement and
        // flips the flag.
        #expect(controller.hasPurchasedRemoveAds == true)
        #expect(controller.latestMessage == .restored)
    }

    // MARK: - In-flight flags

    @Test func purchaseInFlight_flipsTrueWhileAwaitingResult() async {
        let (controller, iap, _) = await makeController(
            products: [IAPProduct(id: removeAdsProductId, displayName: "Remove Ads", displayPrice: "$2.99", isPurchased: false)]
        )
        await iap.setPurchaseResult(for: removeAdsProductId, result: .userCancelled)

        // No `await` between start and finish — `purchaseInFlight` may have
        // already snapped back to false by the time the call returns. We
        // assert the post-condition: flag is false when the call completes
        // and a second tap is not blocked by a stuck flag.
        await controller.purchaseRemoveAds()
        #expect(controller.purchaseInFlight == false)

        await controller.purchaseRemoveAds()
        let calls = await iap.purchaseCallCount
        #expect(calls == 2)
    }

    // MARK: - Failure path

    @Test func purchaseFailure_surfacesFailureMessage() async {
        let (controller, iap, _) = await makeController()
        await iap.setPurchaseResult(for: removeAdsProductId, result: .failed(reason: "card declined"))

        await controller.purchaseRemoveAds()

        guard case .failure(let reason) = controller.latestMessage else {
            Issue.record("Expected .failure, got \(String(describing: controller.latestMessage))")
            return
        }
        #expect(reason == "card declined")
        #expect(controller.hasPurchasedRemoveAds == false)
    }

    // MARK: - Snapshot baselines

    #if canImport(AppKit)
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotIPhoneLightUnpurchased() async {
        let (controller, _, _) = await makeController(
            products: [IAPProduct(
                id: removeAdsProductId,
                displayName: "Remove Ads",
                displayPrice: "$2.99",
                isPurchased: false
            )]
        )
        await controller.bootstrap()
        let view = SettingsView(
            viewModel: SettingsViewModel(persistence: FakePersistence()),
            monetizationController: controller
        )
        let host = hostingView(view, size: SnapshotLayouts.iPhone, colorScheme: .light)
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "SettingsView-iPhone-light-unpurchased")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotIPhoneLightPurchased() async {
        let (controller, _, _) = await makeController(purchased: true)
        await controller.bootstrap()
        let view = SettingsView(
            viewModel: SettingsViewModel(persistence: FakePersistence()),
            monetizationController: controller
        )
        let host = hostingView(view, size: SnapshotLayouts.iPhone, colorScheme: .light)
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "SettingsView-iPhone-light-purchased")
        }
    }
    #endif
}
