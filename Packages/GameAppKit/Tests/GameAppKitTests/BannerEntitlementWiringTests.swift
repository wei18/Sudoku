// BannerEntitlementWiringTests — #1058: every path that grants Remove Ads
// collapses the banner immediately. `MonetizationStateController.markPurchased()`
// is reached by a successful purchase, a restore that returns the entitlement,
// and a `.purchased` event from the `purchaseUpdates()` listener; it runs the
// injected `onEntitlementChanged` hook, which `makeGameApp` builds with
// `makeEntitlementChangedHook(bannerSession:)`. These tests use that exact
// wiring, not a copy of it.

import Foundation
import Testing
import MonetizationCore
import MonetizationTesting
import MonetizationUI
@testable import GameAppKit

@MainActor
@Suite("Banner session — entitlement paths collapse the slot (#1058)", .timeLimit(.minutes(1)))
struct BannerEntitlementWiringTests {

    private struct Wired {
        let session: BannerSessionModel
        let controller: MonetizationStateController
        let iap: FakeIAPClient
    }

    private static let product = IAPProduct(
        id: removeAdsProductId,
        displayName: "Remove Ads",
        displayPrice: "$0.99",
        isPurchased: false
    )

    /// A session showing a loaded banner, wired to a controller the way
    /// `makeGameAppCore` wires them.
    private func makeWired() async -> Wired? {
        let store = FakeAdGateStateStore(initial: AdGateState(firstLaunchAt: Date(timeIntervalSince1970: 0)))
        let gate = AdGate(store: store)
        let session = makeBannerSession(
            adProvider: FakeAdProvider(),
            adGate: gate,
            attPrimer: ATTPrimerCoordinator(isNotDetermined: { false }, requestSystemPrompt: {})
        )
        let iap = FakeIAPClient()
        let controller = MonetizationStateController(
            iapClient: iap,
            stateStore: store,
            adGate: gate,
            onEntitlementChanged: makeEntitlementChangedHook(bannerSession: session)
        )
        let slot = BannerSlotID()
        session.register(slot)
        await session.start()
        guard await eventually({ session.isVisible && session.status(for: slot) != .notInitialized }) else {
            return nil
        }
        return Wired(session: session, controller: controller, iap: iap)
    }

    @Test("a successful purchase collapses the slot")
    func purchaseCollapses() async throws {
        let wired = try #require(await makeWired(), "precondition: banner visible and loaded")
        await wired.iap.setPurchaseResult(for: removeAdsProductId, result: .success(Self.product))

        await wired.controller.purchaseRemoveAds()

        #expect(!wired.session.isVisible)
    }

    @Test("a restore that returns the entitlement collapses the slot")
    func restoreCollapses() async throws {
        let wired = try #require(await makeWired(), "precondition: banner visible and loaded")
        await wired.iap.setProducts([Self.product])

        await wired.controller.restorePurchases()

        #expect(!wired.session.isVisible)
    }

    @Test("a .purchased event from the updates listener collapses the slot")
    func updatesListenerCollapses() async throws {
        let wired = try #require(await makeWired(), "precondition: banner visible and loaded")
        wired.controller.startListeningForLifetimeOfApp()

        await wired.iap.emit(.purchased(productId: removeAdsProductId))

        #expect(await eventually { !wired.session.isVisible })
        await wired.iap.finishUpdates()
    }

    @Test("a restore with nothing to restore leaves the banner")
    func emptyRestoreKeepsBanner() async throws {
        let wired = try #require(await makeWired(), "precondition: banner visible and loaded")

        await wired.controller.restorePurchases()

        #expect(wired.session.isVisible)
    }
}

/// Polls `condition` every 10ms until it holds or `timeout` elapses.
@MainActor
private func eventually(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        if ContinuousClock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}
