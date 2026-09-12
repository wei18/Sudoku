import Foundation
import SwiftUI
import Testing
import MonetizationCore
import MonetizationTesting
@testable import MonetizationUI

// #1058 Phase 2b.1: rows for the spec resolutions the 2b checkpoint found
// unpinned (refreshGate's open-gate branch, a handle arriving after its load
// was cancelled, stale load cleanup, a suppressed load result) and for rulings
// (b) `bannerView(for:)` and (c) trigger-aware retry of a failed slot.

@MainActor
@Suite("BannerSessionModel — checkpoint follow-ups (#1058)", .timeLimit(.minutes(1)))
struct BannerSessionModelFollowUpTests {

    @Test("refreshGate() with the gate still open keeps every banner")
    func refreshGateWithOpenGateKeepsBanner() async {
        let provider = FakeAdProvider()
        let (gate, _) = SessionFixture.gate(SessionFixture.openState)
        let model = BannerSessionModel(adProvider: provider, adGate: gate, now: { SessionFixture.today })
        let slot = BannerSlotID()
        model.register(slot)
        await model.start()
        #expect(await eventually { model.status(for: slot).loadedHandle != nil }, "precondition: slot loaded")
        let loaded = model.status(for: slot)

        await model.refreshGate()

        #expect(model.isVisible)
        #expect(model.status(for: slot) == loaded)
        #expect(await provider.disposedHandles.isEmpty)
    }

    @Test("A handle that arrives after its load was cancelled is disposed, not leaked")
    func lateHandleAfterCancellationIsDisposed() async {
        let provider = HeldLoadAdProvider(loads: 1)
        let (gate, _) = SessionFixture.gate(SessionFixture.openState)
        let model = BannerSessionModel(adProvider: provider, adGate: gate, now: { SessionFixture.today })
        model.register(BannerSlotID())
        await model.start()
        #expect(await eventually { provider.started[0].isOpen }, "precondition: load in flight")

        await model.dismiss()
        provider.release[0].open()

        #expect(await eventually {
            let issued = await provider.issued
            let disposed = await provider.disposed
            return issued.count == 1 && disposed == issued
        }, "the cancelled load's handle must be disposed")
        #expect(!model.isVisible)
    }

    @Test("A cancelled load's cleanup leaves the newer load for the same slot in place")
    func staleLoadCleanupKeepsNewerLoad() async throws {
        let clock = TestClock(SessionFixture.today)
        let provider = HeldLoadAdProvider(loads: 3)
        let (gate, _) = SessionFixture.gate(SessionFixture.openState)
        let model = BannerSessionModel(adProvider: provider, adGate: gate, now: { clock.now })
        let slot = BannerSlotID()
        model.register(slot)
        await model.start()
        #expect(await eventually { provider.started[0].isOpen }, "precondition: load 1 in flight")

        await model.dismiss()
        clock.advance(days: 1)
        await model.sceneDidBecomeActive()
        provider.release[0].open()
        #expect(await eventually { await provider.disposed.count == 1 }, "precondition: load 1 returned late")
        #expect(await eventually { provider.started[1].isOpen }, "precondition: load 2 in flight")
        // Let load 1's cleanup finish on the main actor before the next trigger.
        try await Task.sleep(for: .milliseconds(50))

        await model.sceneDidBecomeActive()
        try await Task.sleep(for: .milliseconds(200))
        #expect(!provider.started[2].isOpen, "a third load means load 1's cleanup dropped load 2's entry")

        provider.releaseAll()
        #expect(await eventually { model.status(for: slot).loadedHandle != nil })
    }

    @Test("A load that finds the gate closed collapses every slot, not just its own")
    func suppressedLoadResultHidesEverySlot() async {
        let provider = FakeAdProvider()
        let (gate, _) = SessionFixture.gate(SessionFixture.openState)
        let model = BannerSessionModel(adProvider: provider, adGate: gate, now: { SessionFixture.today })
        let loadedSlot = BannerSlotID()
        model.register(loadedSlot)
        await model.start()
        #expect(await eventually { model.status(for: loadedSlot).loadedHandle != nil }, "precondition: first slot loaded")
        guard let handle = model.status(for: loadedSlot).loadedHandle else { return }

        // The gate closes without the model hearing about it, so the next load
        // is the first to see `.suppressed`.
        await gate.recordPurchase()
        model.register(BannerSlotID())

        #expect(await eventually { !model.isVisible })
        #expect(model.status(for: loadedSlot) == .notInitialized)
        #expect(await eventually { await provider.disposedHandles == [handle] })
        #expect(await provider.refreshCallCount == 1)
    }

    @Test("bannerView(for:) returns the host's view for a loaded slot, nil otherwise")
    func bannerViewOnlyForLoadedHostedSlot() async {
        let (hostedGate, _) = SessionFixture.gate(SessionFixture.openState)
        let hosted = BannerSessionModel(adProvider: HostingAdProvider(), adGate: hostedGate, now: { SessionFixture.today })
        let hostedSlot = BannerSlotID()
        #expect(hosted.bannerView(for: hostedSlot) == nil, "no handle yet")
        hosted.register(hostedSlot)
        await hosted.start()
        #expect(await eventually { hosted.status(for: hostedSlot).loadedHandle != nil }, "precondition: loaded")
        #expect(hosted.bannerView(for: hostedSlot) != nil)

        let (plainGate, _) = SessionFixture.gate(SessionFixture.openState)
        let noHost = BannerSessionModel(adProvider: FakeAdProvider(), adGate: plainGate, now: { SessionFixture.today })
        let noHostSlot = BannerSlotID()
        noHost.register(noHostSlot)
        await noHost.start()
        #expect(await eventually { noHost.status(for: noHostSlot).loadedHandle != nil }, "precondition: loaded")
        #expect(noHost.bannerView(for: noHostSlot) == nil, "a provider without a view host has nothing to show")

        let (suppressedGate, _) = SessionFixture.gate(SessionFixture.openState)
        let suppressed = BannerSessionModel(
            adProvider: HostingAdProvider(status: .suppressed),
            adGate: suppressedGate,
            now: { SessionFixture.today }
        )
        let suppressedSlot = BannerSlotID()
        suppressed.register(suppressedSlot)
        await suppressed.start()
        #expect(suppressed.providerSuppressed)
        #expect(suppressed.bannerView(for: suppressedSlot) == nil)
    }

    @Test("A failed slot retries only on its own registration or a repoll")
    func failedSlotRetriesOnlyOnItsOwnTrigger() async throws {
        struct LoadError: Error {}
        let provider = FakeAdProvider(scripted: ScriptedAdProviderState(refreshThrows: LoadError()))
        let (gate, _) = SessionFixture.gate(SessionFixture.openState)
        let model = BannerSessionModel(adProvider: provider, adGate: gate, now: { SessionFixture.today })
        let slotA = BannerSlotID()
        model.register(slotA)
        await model.start()
        #expect(await eventually { model.status(for: slotA).isFailed }, "precondition: A failed")
        await provider.script(ScriptedAdProviderState())

        let slotB = BannerSlotID()
        model.register(slotB)
        #expect(await eventually { model.status(for: slotB).loadedHandle != nil })
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.status(for: slotA).isFailed, "B's registration must not retry A")
        #expect(await provider.refreshCallCount == 2)

        await model.sceneDidBecomeActive()
        #expect(await eventually { model.status(for: slotA).loadedHandle != nil }, "a repoll retries A")
        #expect(await provider.refreshCallCount == 3)

        let slotC = BannerSlotID()
        await provider.script(ScriptedAdProviderState(refreshThrows: LoadError()))
        model.register(slotC)
        #expect(await eventually { model.status(for: slotC).isFailed }, "precondition: C failed")
        await provider.script(ScriptedAdProviderState())
        model.unregister(slotC)
        model.register(slotC)
        #expect(await eventually { model.status(for: slotC).loadedHandle != nil }, "re-registering C retries it")
    }
}
