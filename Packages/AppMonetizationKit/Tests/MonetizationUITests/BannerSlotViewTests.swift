// BannerSlotViewTests — the pure renderer and its registration (#1058 slot-model
// spec rows B1, S1, I1, M1 and Pause).
//
// Every view is hosted in a bare `NSHostingView`; registration is observed
// through the session (`slots`) and the fake provider (`refreshCallCount`,
// `disposedHandles`), never through the rendered subtree.

#if canImport(AppKit)

import AppKit
import Foundation
import SwiftUI
import Testing

import MonetizationCore
import MonetizationTesting
@testable import MonetizationUI

@MainActor
@Suite("BannerSlotView — renderer + registration (#1058)", .timeLimit(.minutes(1)))
struct BannerSlotViewTests {

    static let bookend: CGFloat = 102
    static let gap: CGFloat = 12

    /// Why a slot renders nothing. Every case must add zero subviews.
    enum HiddenReason: String, CaseIterable, Sendable, CustomStringConvertible {
        case disabledSession
        case gatePending
        case gateClosed
        case providerSuppressed
        case hostSuppressed

        var description: String { rawValue }
    }

    // MARK: - Fixtures

    private func session(
        provider: FakeAdProvider = FakeAdProvider(),
        state: AdGateState = SessionFixture.openState
    ) -> BannerSessionModel {
        let (gate, _) = SessionFixture.gate(state)
        return BannerSessionModel(adProvider: provider, adGate: gate, now: { SessionFixture.today })
    }

    private func startedSession(
        provider: FakeAdProvider = FakeAdProvider(),
        state: AdGateState = SessionFixture.openState
    ) async -> BannerSessionModel {
        let model = session(provider: provider, state: state)
        await model.start()
        return model
    }

    private func measuredHeight(of view: some View) -> CGFloat {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 320, height: 1_000)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    private func mount(_ root: SlotHost) -> NSHostingView<SlotHost> {
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(x: 0, y: 0, width: 320, height: 400)
        host.layoutSubtreeIfNeeded()
        return host
    }

    private func update(_ host: NSHostingView<SlotHost>, to root: SlotHost) {
        host.rootView = root
        host.layoutSubtreeIfNeeded()
    }

    private func loadedHandleIDs(_ model: BannerSessionModel) -> Set<UUID> {
        Set(model.slots.values.compactMap { $0.loadedHandle?.id })
    }

    /// Lets any load a regression would schedule reach the provider.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(300))
    }

    // MARK: - B1: a hidden slot adds no subview

    @Test("B1: a hidden slot adds no spacing to a parent stack", arguments: HiddenReason.allCases)
    func hiddenSlotAddsNoSubview(reason: HiddenReason) async {
        let model: BannerSessionModel
        var isSuppressed = false
        switch reason {
        case .disabledSession:
            model = .disabled
        case .gatePending:
            model = session()
        case .gateClosed:
            model = await startedSession(
                state: AdGateState(firstLaunchAt: SessionFixture.firstLaunch, hasPurchasedRemoveAds: true)
            )
        case .providerSuppressed:
            model = await startedSession(
                provider: FakeAdProvider(scripted: ScriptedAdProviderState(statusSequence: [.suppressed]))
            )
        case .hostSuppressed:
            model = await startedSession()
            isSuppressed = true
        }
        #expect(!model.isVisible || isSuppressed)

        let height = measuredHeight(
            of: Bookends(slot: BannerSlotView(isSuppressed: isSuppressed))
                .environment(\.bannerSession, model)
        )

        #expect(height == 2 * Self.bookend + Self.gap, "\(reason): hidden slot measured \(height)pt")
    }

    @Test("B1 sanity: a visible slot adds its 50pt band and one more gap")
    func visibleSlotAddsBand() async {
        let model = await startedSession(provider: FakeAdProvider(readinessHeld: true))

        let height = measuredHeight(
            of: Bookends(slot: BannerSlotView(isSuppressed: false))
                .environment(\.bannerSession, model)
        )

        #expect(height == 2 * Self.bookend + 2 * Self.gap + 50)
    }

    // MARK: - S1: registration lives on the view node

    @Test("S1: a slot that renders nothing still registers, and loads once the gate opens")
    func hiddenSlotRegisters() async {
        let provider = FakeAdProvider()
        let model = session(provider: provider)
        let host = mount(SlotHost(session: model))
        #expect(model.shouldShow == nil)

        await model.start()

        #expect(await eventually { model.slots.count == 1 && loadedHandleIDs(model).count == 1 })
        #expect(await provider.refreshCallCount == 1)
        _ = host
    }

    @Test("S1: each slot identity holds its own lease")
    func eachIdentityLeasesOnce() async {
        let provider = FakeAdProvider()
        let model = await startedSession(provider: provider)
        let host = mount(SlotHost(session: model, slotCount: 2))

        #expect(await eventually { loadedHandleIDs(model).count == 2 })
        #expect(await provider.refreshCallCount == 2)
        _ = host
    }

    @Test("S1: removing a slot unregisters it and disposes its handle")
    func removalUnregisters() async {
        let provider = FakeAdProvider()
        let model = await startedSession(provider: provider)
        let host = mount(SlotHost(session: model))
        #expect(await eventually { loadedHandleIDs(model).count == 1 })
        let loaded = loadedHandleIDs(model)

        update(host, to: SlotHost(session: model, slotCount: 0))

        #expect(await eventually {
            host.layoutSubtreeIfNeeded()
            return model.slots.isEmpty
        })
        #expect(await eventually { await Set(provider.disposedHandles.map(\.id)) == loaded })
    }

    // MARK: - I1: attach is idempotent

    /// Mutation target: drop `guard self.session !== session` in
    /// `BannerSlotLease.attach(to:)`.
    @Test("I1: re-rendering a slot with the same session never re-requests its banner")
    func reRenderDoesNotChurn() async {
        let provider = FakeAdProvider()
        let model = await startedSession(provider: provider)
        let host = mount(SlotHost(session: model))
        #expect(await eventually { loadedHandleIDs(model).count == 1 })
        let handles = loadedHandleIDs(model)

        for padding in [4, 8, 12] as [CGFloat] {
            update(host, to: SlotHost(session: model, padding: padding))
            await settle()
        }

        #expect(await provider.refreshCallCount == 1)
        #expect(await provider.disposedHandles.isEmpty)
        #expect(loadedHandleIDs(model) == handles)
    }

    // MARK: - M1: a lost injection is reported

    /// Mutation target: drop the `onMissingSession()` call from
    /// `BannerSlotRegistration.update()`'s nil branch.
    @Test("M1: a slot with no session in its environment reports it and renders nothing")
    func missingSessionIsReported() {
        let calls = CallBox()
        let original = BannerSessionModel.onMissingSession
        BannerSessionModel.onMissingSession = { calls.count += 1 }
        defer { BannerSessionModel.onMissingSession = original }

        let height = measuredHeight(of: Bookends(slot: BannerSlotView(isSuppressed: false)))

        #expect(calls.count > 0)
        #expect(height == 2 * Self.bookend + Self.gap)
    }

    // MARK: - Pause

    @Test("Pause: suppressing and restoring a slot keeps its lease and its banner")
    func pauseKeepsLease() async {
        let provider = FakeAdProvider()
        let model = await startedSession(provider: provider)
        let host = mount(SlotHost(session: model))
        #expect(await eventually { loadedHandleIDs(model).count == 1 })
        let handles = loadedHandleIDs(model)
        host.layoutSubtreeIfNeeded()
        let shownHeight = host.fittingSize.height
        #expect(shownHeight > 0)

        update(host, to: SlotHost(session: model, isSuppressed: true))
        #expect(host.fittingSize.height == 0)
        await settle()

        update(host, to: SlotHost(session: model, isSuppressed: false))
        #expect(host.fittingSize.height == shownHeight)
        await settle()

        #expect(await provider.refreshCallCount == 1)
        #expect(await provider.disposedHandles.isEmpty)
        #expect(loadedHandleIDs(model) == handles)
    }
}

// MARK: - Hosts

private struct Bookends<Slot: View>: View {
    let slot: Slot

    var body: some View {
        VStack(spacing: BannerSlotViewTests.gap) {
            Color.red.frame(width: 100, height: BannerSlotViewTests.bookend)
            slot
            Color.blue.frame(width: 100, height: BannerSlotViewTests.bookend)
        }
    }
}

private struct SlotHost: View {
    let session: BannerSessionModel?
    var slotCount = 1
    var isSuppressed = false
    var padding: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<slotCount, id: \.self) { _ in
                BannerSlotView(isSuppressed: isSuppressed, horizontalPadding: padding)
            }
        }
        .environment(\.bannerSession, session)
    }
}

@MainActor
private final class CallBox {
    var count = 0
}

#endif
