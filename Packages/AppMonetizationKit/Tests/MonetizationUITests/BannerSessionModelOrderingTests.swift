import Foundation
import Observation
import Testing
import MonetizationCore
import MonetizationTesting
@testable import MonetizationUI

// #1058 slot-model spec, "PM 2" and "PM 1": provider readiness is awaited once
// per session, the primer is requested before any load, and a cancelled wait
// writes no status.

@MainActor
@Suite("BannerSessionModel — readiness, primer and cancellation ordering (#1058)", .timeLimit(.minutes(1)))
struct BannerSessionModelOrderingTests {

    @Test("R1: readiness is awaited once per session, not once per slot")
    func readinessAwaitedOncePerSession() async {
        let provider = FakeAdProvider(readinessHeld: true)
        let primer = CallCounter()
        let (gate, _) = SessionFixture.gate(SessionFixture.openState)
        let model = BannerSessionModel(
            adProvider: provider,
            adGate: gate,
            onAdContext: { await primer.increment() },
            now: { SessionFixture.today }
        )
        let slotA = BannerSlotID()
        let slotB = BannerSlotID()
        let slotC = BannerSlotID()

        model.register(slotA)
        model.register(slotB)
        await model.start()
        provider.markReady()
        #expect(await eventually {
            model.status(for: slotA).loadedHandle != nil && model.status(for: slotB).loadedHandle != nil
        })

        model.register(slotC)
        #expect(await eventually { model.status(for: slotC).loadedHandle != nil })

        #expect(await provider.awaitReadyCallCount == 1)
        #expect(await primer.count == 1)
    }

    @Test("B2: a repoll with readiness held reaches neither the primer nor the provider's load")
    func repollWaitsForReadiness() async throws {
        let provider = FakeAdProvider(readinessHeld: true)
        let primer = CallCounter()
        let (gate, _) = SessionFixture.gate(SessionFixture.openState)
        let model = BannerSessionModel(
            adProvider: provider,
            adGate: gate,
            onAdContext: { await primer.increment() },
            now: { SessionFixture.today }
        )
        model.register(BannerSlotID())

        await model.sceneDidBecomeActive()
        try await Task.sleep(for: .milliseconds(500))

        #expect(await provider.refreshCallCount == 0, "no load may start before provider readiness")
        #expect(await primer.count == 0, "the primer must not run before provider readiness")

        provider.markReady()
        #expect(await eventually {
            let refreshes = await provider.refreshCallCount
            let primed = await primer.count
            return refreshes == 1 && primed == 1
        })
    }

    @Test("B2′: readiness, then the primer, then the first ad load")
    func readinessThenPrimerThenLoad() async {
        let log = EventLog()
        let readiness = ReadinessLatch()
        let provider = OrderRecordingAdProvider(log: log, readiness: readiness)
        let (gate, _) = SessionFixture.gate(SessionFixture.openState)
        let model = BannerSessionModel(
            adProvider: provider,
            adGate: gate,
            onAdContext: {
                // A primer request that takes a moment: a load that does not
                // wait for it to return would log "adLoadStarted" first.
                try? await Task.sleep(for: .milliseconds(200))
                await log.record("primer")
            },
            now: { SessionFixture.today }
        )
        model.register(BannerSlotID())

        // 500ms margin: a load gated on mount instead of readiness would
        // record "adLoadStarted" before "ready".
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            await log.record("ready")
            readiness.open()
        }
        await model.start()

        #expect(await eventually(timeout: .seconds(3)) { await log.events.count >= 3 })
        #expect(await log.events == ["ready", "primer", "adLoadStarted"])
    }

    @Test("C3: a cancelled wait produces no status change")
    func cancelledWaitWritesNothing() async throws {
        let provider = FakeAdProvider(readinessHeld: true)
        let (gate, _) = SessionFixture.gate(SessionFixture.openState)
        let model = BannerSessionModel(adProvider: provider, adGate: gate, now: { SessionFixture.today })
        let slotA = BannerSlotID()
        let slotB = BannerSlotID()
        model.register(slotA)
        model.register(slotB)
        await model.start()
        // Let both loads reach their `sessionReady` wait.
        try await Task.sleep(for: .milliseconds(50))

        let changed = ChangeFlag()
        withObservationTracking {
            _ = model.status(for: slotB)
            _ = model.shouldShow
        } onChange: {
            changed.set()
        }

        model.unregister(slotA)
        try await Task.sleep(for: .milliseconds(300))
        #expect(!changed.isSet, "cancelling slot A's wait must not write any status")

        provider.markReady()
        #expect(await eventually { model.status(for: slotB).loadedHandle != nil })
        #expect(await provider.refreshCallCount == 1)
        #expect(model.slots[slotA] == nil)
        #expect(!model.slots.values.contains { $0.isFailed })
    }
}
