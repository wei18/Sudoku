// HomeViewRemoveAdsCardTests — v2.3.6.
//
// HomeView surfaces a 5th "Remove Ads" mode card when an unpurchased
// `MonetizationStateController` is injected. We assert the behavior path
// (controller drives visibility + tap → purchase) rather than walking the
// SwiftUI body — the visual contract is pinned by the new snapshot baseline
// (`HomeView-iPhone-light-with-remove-ads-card`).

import Foundation
import SnapshotTesting
import SwiftUI
import Testing

import MonetizationCore
import MonetizationTesting
@testable import SudokuUI

@MainActor
@Suite("HomeView — 5th Remove Ads card")
struct HomeViewRemoveAdsCardTests {

    private func makeController(
        purchased: Bool,
        products: [IAPProduct] = []
    ) async -> (MonetizationStateController, FakeIAPClient) {
        let store = FakeAdGateStateStore(
            initial: AdGateState(
                firstLaunchAt: Date(timeIntervalSince1970: 0),
                hasPurchasedRemoveAds: purchased
            )
        )
        let iap = FakeIAPClient()
        await iap.setProducts(products)
        let gate = AdGate(store: store)
        let controller = MonetizationStateController(
            iapClient: iap,
            stateStore: store,
            adGate: gate
        )
        await controller.bootstrap()
        return (controller, iap)
    }

    // MARK: - Unpurchased → 5th card visible

    @Test func unpurchasedController_exposesRemoveAdsCardState() async {
        let (controller, _) = await makeController(purchased: false)
        // HomeView's body reads `controller.hasPurchasedRemoveAds` to decide
        // whether to render the 5th card. Asserting the controller state
        // here is the behavioral pre-image of that visibility check.
        #expect(controller.hasPurchasedRemoveAds == false)
    }

    // MARK: - Purchased → no 5th card

    @Test func purchasedController_suppressesRemoveAdsCardState() async {
        let (controller, _) = await makeController(purchased: true)
        #expect(controller.hasPurchasedRemoveAds == true)
    }

    // MARK: - Tap → same purchase flow as Settings row

    @Test func tappingCard_invokesPurchaseFlow() async {
        let (controller, iap) = await makeController(
            purchased: false,
            products: [IAPProduct(
                id: removeAdsProductId,
                displayName: "Remove Ads",
                displayPrice: "$2.99",
                isPurchased: false
            )]
        )
        let purchased = IAPProduct(
            id: removeAdsProductId,
            displayName: "Remove Ads",
            displayPrice: "$2.99",
            isPurchased: true
        )
        await iap.setPurchaseResult(for: removeAdsProductId, result: .success(purchased))

        // HomeView's card binds its tap action to `controller.purchaseRemoveAds()`.
        await controller.purchaseRemoveAds()

        let calls = await iap.purchaseCallCount
        #expect(calls == 1)
        #expect(controller.hasPurchasedRemoveAds == true)
    }

    // MARK: - Snapshot baseline

    #if canImport(AppKit)
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotIPhoneLightWithRemoveAdsCard() async {
        let (controller, _) = await makeController(
            purchased: false,
            products: [IAPProduct(
                id: removeAdsProductId,
                displayName: "Remove Ads",
                displayPrice: "$2.99",
                isPurchased: false
            )]
        )
        let host = hostingView(
            HomeView(viewModel: HomeViewModel(), monetizationController: controller),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "HomeView-iPhone-light-with-remove-ads-card")
        }
    }
    #endif
}
