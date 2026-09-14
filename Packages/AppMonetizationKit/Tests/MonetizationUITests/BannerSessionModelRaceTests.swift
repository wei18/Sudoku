// BannerSessionModelRaceTests — a hide that lands while `runStart` or
// `sceneDidBecomeActive` is suspended must not be overwritten by their later
// publish, and the bail must not wedge the session: the next open repoll shows
// the banner and loads it exactly once (#1058 2c.1, MINOR-3). Each row holds
// the gate read in one window.

import Foundation
import Testing

import MonetizationCore
import MonetizationTesting
@testable import MonetizationUI

/// Holds the first `loadState()` (when asked) or the next `saveState(_:)`
/// after `armNextSave()` until the test opens `release`. The hold ignores
/// cancellation — it models a store round trip already in flight — so the
/// awaiting `AdGate` read really is suspended there. A load returns the state
/// scripted when it began.
private actor HeldAdGateStateStore: AdGateStateStore {
    nonisolated let entered = ReadinessLatch()
    nonisolated let release = ReadinessLatch()
    private var state: AdGateState
    private var holdNextLoad: Bool
    private var holdNextSave = false

    init(initial: AdGateState, holdFirstLoad: Bool = false) {
        state = initial
        holdNextLoad = holdFirstLoad
    }

    func script(_ newState: AdGateState) {
        state = newState
    }

    func armNextSave() {
        holdNextSave = true
    }

    func loadState() async throws -> AdGateState {
        let snapshot = state
        if holdNextLoad {
            holdNextLoad = false
            await holdUntilReleased()
        }
        return snapshot
    }

    func saveState(_ newState: AdGateState) async throws {
        if holdNextSave {
            holdNextSave = false
            await holdUntilReleased()
        }
    }

    private func holdUntilReleased() async {
        entered.open()
        while !release.isOpen {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

@MainActor
@Suite("BannerSessionModel — a hide wins over a suspended publish (#1058)", .timeLimit(.minutes(1)))
struct BannerSessionModelRaceTests {

    /// Reopens the gate (the closing dismissal was "today") and repolls once:
    /// the banner comes back and loads exactly once.
    private func expectRecovers(_ model: BannerSessionModel, _ provider: FakeAdProvider, clock: TestClock) async {
        let refreshesAfterBail = await provider.refreshCallCount
        clock.advance(days: 1)

        await model.sceneDidBecomeActive()

        #expect(model.isVisible, "a bail must not wedge the session: the next open repoll shows the banner")
        #expect(await eventually { model.slots.values.contains { $0.loadedHandle != nil } })
        try? await Task.sleep(for: .milliseconds(300))
        #expect(await provider.refreshCallCount == refreshesAfterBail + 1)
    }

    /// Mutation target: drop both `hideGeneration == generation` checks in
    /// `runStart`.
    @Test("start window: a hide during runStart's gate read is not overwritten, and the session recovers")
    func hideDuringStartReadWins() async throws {
        let store = HeldAdGateStateStore(initial: SessionFixture.openState, holdFirstLoad: true)
        let clock = TestClock(SessionFixture.today)
        let gate = AdGate(store: store, calendar: SessionFixture.calendar)
        let provider = FakeAdProvider()
        let model = BannerSessionModel(adProvider: provider, adGate: gate, now: { clock.now })
        model.register(BannerSlotID())

        let starting = Task { await model.start() }
        try await store.entered.wait()
        await store.script(SessionFixture.dismissedTodayState)
        await model.refreshGate()
        store.release.open()
        await starting.value
        try? await Task.sleep(for: .milliseconds(300))

        #expect(model.isVisible == false)
        #expect(await provider.refreshCallCount == 0)

        await expectRecovers(model, provider, clock: clock)
    }

    /// Mutation target: drop the `hideGeneration == generation` check in
    /// `sceneDidBecomeActive`.
    @Test("repoll window: a hide during sceneDidBecomeActive's gate read is not overwritten, and the session recovers")
    func hideDuringRepollReadWins() async throws {
        let store = HeldAdGateStateStore(initial: SessionFixture.openState)
        let clock = TestClock(SessionFixture.today)
        let gate = AdGate(store: store, calendar: SessionFixture.calendar)
        let provider = FakeAdProvider()
        let model = BannerSessionModel(adProvider: provider, adGate: gate, now: { clock.now })
        model.register(BannerSlotID())
        await model.start()
        #expect(await eventually { model.slots.values.contains { $0.loadedHandle != nil } })
        let refreshesBefore = await provider.refreshCallCount

        // Past the 6h wall-clock write throttle (still the same day), so the
        // repoll's gate read persists — and suspends — inside `shouldShowBanner`.
        clock.advance(days: 0.3)
        await store.armNextSave()
        let repolling = Task { await model.sceneDidBecomeActive() }
        try await store.entered.wait()
        await gate.recordBannerDismissed(now: clock.now)
        await model.refreshGate()
        store.release.open()
        await repolling.value

        #expect(model.isVisible == false)
        #expect(await provider.refreshCallCount == refreshesBefore)

        await expectRecovers(model, provider, clock: clock)
    }
}
