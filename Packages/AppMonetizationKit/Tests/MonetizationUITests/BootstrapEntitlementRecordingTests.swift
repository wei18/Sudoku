// BootstrapEntitlementRecordingTests — `bootstrap()` must record a StoreKit
// entitlement the monetization store does not yet know about (#1074).
//
// Every other entitlement path (purchase success, restore, `.purchased`
// listener event) routes through `markPurchased()`, which writes the flag
// into `AdGate`. `bootstrap()` used to flip only the local
// `hasPurchasedRemoveAds`, so a purchaser whose store lacked the record
// kept seeing banners on every launch while Settings showed them as purchased.
//
// Mutation target: revert the bootstrap branch to `hasPurchasedRemoveAds = true`.

import Foundation
import Testing

import MonetizationCore
import MonetizationTesting
@testable import MonetizationUI

@MainActor
@Suite("MonetizationStateController — bootstrap records the StoreKit entitlement (#1074)", .timeLimit(.minutes(1)))
struct BootstrapEntitlementRecordingTests {

    @MainActor
    private final class HookCounter {
        var count = 0
    }

    private struct Fixture {
        let controller: MonetizationStateController
        let gate: AdGate
        let store: FakeAdGateStateStore
        let hook: HookCounter
    }

    /// Store seeded with a first-launch state and (by default) NO purchase
    /// record, so the gate would show a banner unless bootstrap records the
    /// entitlement.
    private func makeFixture(purchased: Bool, storeRecordsPurchase: Bool = false) async -> Fixture {
        let iap = FakeIAPClient()
        await iap.setProducts([
            IAPProduct(id: removeAdsProductId, displayName: "Remove Ads", displayPrice: "$0.99", isPurchased: purchased),
        ])
        let store = FakeAdGateStateStore(initial: AdGateState(
            firstLaunchAt: Date(timeIntervalSince1970: 0),
            hasPurchasedRemoveAds: storeRecordsPurchase
        ))
        let gate = AdGate(store: store)
        let hook = HookCounter()
        let controller = MonetizationStateController(
            iapClient: iap,
            stateStore: store,
            adGate: gate,
            onEntitlementChanged: { hook.count += 1 }
        )
        return Fixture(controller: controller, gate: gate, store: store, hook: hook)
    }

    @Test("StoreKit entitlement + empty store: bootstrap closes the gate and persists the record")
    func bootstrapRecordsEntitlementInAdGate() async {
        let fixture = await makeFixture(purchased: true)
        #expect(await fixture.gate.shouldShowBanner(now: Date()) == true)

        await fixture.controller.bootstrap()

        #expect(fixture.controller.hasPurchasedRemoveAds == true)
        #expect(await fixture.gate.shouldShowBanner(now: Date()) == false)
        #expect(await fixture.store.peekState()?.hasPurchasedRemoveAds == true)
        #expect(fixture.hook.count == 1)
    }

    @Test("repeat bootstrap does not re-fire the entitlement hook")
    func repeatBootstrapIsIdempotent() async {
        let fixture = await makeFixture(purchased: true)

        await fixture.controller.bootstrap()
        await fixture.controller.bootstrap()

        #expect(fixture.hook.count == 1)
    }

    @Test("store already records the purchase: bootstrap does not fire the hook")
    func bootstrapSkipsHookWhenStoreAlreadyRecorded() async {
        let fixture = await makeFixture(purchased: true, storeRecordsPurchase: true)

        await fixture.controller.bootstrap()

        #expect(fixture.controller.hasPurchasedRemoveAds == true)
        #expect(await fixture.gate.shouldShowBanner(now: Date()) == false)
        #expect(fixture.hook.count == 0)
    }

    @Test("unpurchased product: bootstrap leaves the gate open and never records")
    func bootstrapDoesNotRecordWithoutEntitlement() async {
        let fixture = await makeFixture(purchased: false)

        await fixture.controller.bootstrap()

        #expect(fixture.controller.hasPurchasedRemoveAds == false)
        #expect(await fixture.gate.shouldShowBanner(now: Date()) == true)
        #expect(await fixture.store.peekState()?.hasPurchasedRemoveAds == false)
        #expect(fixture.hook.count == 0)
    }
}
