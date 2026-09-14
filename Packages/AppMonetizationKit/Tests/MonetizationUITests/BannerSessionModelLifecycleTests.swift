import Foundation
import Testing
import MonetizationCore
import MonetizationTesting
@testable import MonetizationUI

// #1058 slot-model spec, "Start, ordering, repoll", "PM 3", "Split state,
// dismiss, purchase" and "Pause": what the session model publishes across a
// session's lifecycle.

@MainActor
@Suite("BannerSessionModel — gate, slots and lifecycle (#1058)", .timeLimit(.minutes(1)))
struct BannerSessionModelLifecycleTests {

    private func loadedHandles(_ model: BannerSessionModel, _ ids: BannerSlotID...) async -> [AdBannerHandle]? {
        let allLoaded = await eventually { ids.allSatisfy { model.status(for: $0).loadedHandle != nil } }
        guard allLoaded else { return nil }
        return ids.compactMap { model.status(for: $0).loadedHandle }
    }

    @Test("Gap 1: a banner dismissed yesterday comes back on the next foreground")
    func repollBringsBackYesterdaysDismissal() async {
        let clock = TestClock(SessionFixture.today)
        let provider = FakeAdProvider()
        let (gate, _) = SessionFixture.gate(SessionFixture.dismissedTodayState)
        let model = BannerSessionModel(adProvider: provider, adGate: gate, now: { clock.now })
        let slot = BannerSlotID()
        model.register(slot)

        await model.start()
        #expect(model.shouldShow == false, "precondition: dismissed today")

        clock.advance(days: 1)
        await model.sceneDidBecomeActive()

        #expect(model.shouldShow == true)
        #expect(await loadedHandles(model, slot) != nil)
    }

    @Test("Gap 2: mounted slots hold distinct handles and dispose independently")
    func slotsHoldDistinctHandles() async {
        let provider = FakeAdProvider()
        let (gate, _) = SessionFixture.gate(SessionFixture.openState)
        let model = BannerSessionModel(adProvider: provider, adGate: gate, now: { SessionFixture.today })
        let slotA = BannerSlotID()
        let slotB = BannerSlotID()
        model.register(slotA)
        model.register(slotB)
        await model.start()

        guard let handles = await loadedHandles(model, slotA, slotB) else {
            Issue.record("both slots should load")
            return
        }
        #expect(handles[0] != handles[1], "each slot must hold its own banner handle")

        model.unregister(slotA)
        #expect(await eventually { await provider.disposedHandles == [handles[0]] })
        #expect(model.status(for: slotB) == .loaded(handles[1]))
    }

    @Test("Seed: the resolved gate is readable synchronously after start()")
    func resolvedGateReadableSynchronously() async {
        let (gate, _) = SessionFixture.gate(SessionFixture.openState)
        let model = BannerSessionModel(adProvider: FakeAdProvider(), adGate: gate, now: { SessionFixture.today })
        #expect(model.shouldShow == nil, "precondition: nothing resolved yet this session")

        await model.start()

        #expect(model.shouldShow == true)
        #expect(model.isVisible, "a slot mounted now must reserve its banner on its first body")
    }

    @Test("Cold launch: start() resolves the gate with no slot mounted")
    func startResolvesGateWithoutSlots() async {
        let (gate, store) = SessionFixture.gate(SessionFixture.openState)
        let model = BannerSessionModel(adProvider: FakeAdProvider(), adGate: gate, now: { SessionFixture.today })

        await model.start()

        #expect(await store.loadCallCount > 0)
    }

    @Test("Foreground does not reload a slot that already holds a banner")
    func foregroundKeepsLoadedHandle() async throws {
        let provider = FakeAdProvider()
        let (gate, _) = SessionFixture.gate(SessionFixture.openState)
        let model = BannerSessionModel(adProvider: provider, adGate: gate, now: { SessionFixture.today })
        let slot = BannerSlotID()
        model.register(slot)
        await model.start()
        guard let handle = await loadedHandles(model, slot)?.first else {
            Issue.record("slot should load")
            return
        }

        await model.sceneDidBecomeActive()
        await model.sceneDidBecomeActive()
        try await Task.sleep(for: .milliseconds(200))

        #expect(await provider.refreshCallCount == 1)
        #expect(model.status(for: slot) == .loaded(handle))
    }

    @Test("Dismiss hides every slot and disposes every handle")
    func dismissHidesAndDisposes() async {
        let provider = FakeAdProvider()
        let (gate, _) = SessionFixture.gate(SessionFixture.openState)
        let model = BannerSessionModel(adProvider: provider, adGate: gate, now: { SessionFixture.today })
        let slotA = BannerSlotID()
        let slotB = BannerSlotID()
        model.register(slotA)
        model.register(slotB)
        await model.start()
        guard let handles = await loadedHandles(model, slotA, slotB) else {
            Issue.record("both slots should load")
            return
        }

        await model.dismiss()

        #expect(model.shouldShow == false)
        #expect(!model.isVisible)
        #expect(Set(await provider.disposedHandles.map(\.id)) == Set(handles.map(\.id)))
        #expect(await gate.shouldShowBanner(now: SessionFixture.today) == false, "today's dismissal is recorded")
    }

    @Test("Purchase: refreshGate() hides without loading or waiting on the provider")
    func purchaseHidesWithoutLoading() async {
        let provider = FakeAdProvider()
        let (gate, _) = SessionFixture.gate(SessionFixture.openState)
        let model = BannerSessionModel(adProvider: provider, adGate: gate, now: { SessionFixture.today })
        let slot = BannerSlotID()
        model.register(slot)
        await model.start()
        guard let handle = await loadedHandles(model, slot)?.first else {
            Issue.record("slot should load")
            return
        }
        await gate.recordPurchase()
        let refreshesBefore = await provider.refreshCallCount
        let readinessBefore = await provider.awaitReadyCallCount

        await model.refreshGate()

        #expect(!model.isVisible)
        #expect(await provider.refreshCallCount == refreshesBefore)
        #expect(await provider.awaitReadyCallCount == readinessBefore)
        #expect(await provider.disposedHandles == [handle])
    }

    @Test("macOS: a suppressed provider never waits, never primes, never loads")
    func suppressedProviderAtStart() async throws {
        let provider = FakeAdProvider(scripted: .init(statusSequence: [.suppressed]), readinessHeld: true)
        let primer = CallCounter()
        let (gate, _) = SessionFixture.gate(SessionFixture.openState)
        let model = BannerSessionModel(
            adProvider: provider,
            adGate: gate,
            onAdContext: { await primer.increment() },
            now: { SessionFixture.today }
        )
        model.register(BannerSlotID())

        await model.start()
        await model.sceneDidBecomeActive()
        try await Task.sleep(for: .milliseconds(200))

        #expect(model.providerSuppressed)
        #expect(!model.isVisible)
        #expect(await provider.awaitReadyCallCount == 0)
        #expect(await primer.count == 0)
        #expect(await provider.refreshCallCount == 0)
    }

    @Test("macOS: suppression first discovered on a repoll still never waits or primes")
    func suppressedProviderFoundOnRepoll() async throws {
        let clock = TestClock(SessionFixture.today)
        let provider = FakeAdProvider(scripted: .init(statusSequence: [.suppressed]), readinessHeld: true)
        let primer = CallCounter()
        let (gate, _) = SessionFixture.gate(SessionFixture.dismissedTodayState)
        let model = BannerSessionModel(
            adProvider: provider,
            adGate: gate,
            onAdContext: { await primer.increment() },
            now: { clock.now }
        )
        model.register(BannerSlotID())
        await model.start()
        #expect(model.shouldShow == false, "precondition: gate closed at start, suppression not yet checked")

        clock.advance(days: 1)
        await model.sceneDidBecomeActive()
        try await Task.sleep(for: .milliseconds(200))

        #expect(model.providerSuppressed)
        #expect(await provider.awaitReadyCallCount == 0)
        #expect(await primer.count == 0)
    }
}
