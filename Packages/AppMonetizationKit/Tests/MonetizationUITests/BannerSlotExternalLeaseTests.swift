// BannerSlotExternalLeaseTests — pins the externally-owned-lease init added
// for #1080 (`BannerSlotView(lease:...)` / `BannerSlotRegistration(lease:)`).
//
// The production motivation (`GameAppKit.BannerAccessoryView`, hosted inside
// `tabViewBottomAccessory`) is that a native host can re-host a view's
// SwiftUI content under a NEW view identity without re-rendering anything
// above it — see `tabview-bottom-accessory-rehosts-content`. `NSHostingView`
// can't reproduce that native re-host mechanism directly, but the behavior
// under test — a `BannerSlotRegistration` backed by the SAME externally
// owned `BannerSlotLease` must not re-register when ITS OWN view identity
// changes — is exactly what `BannerSlotRegistration.update()` decides, and a
// plain identity swap (`ExternalLeaseHostA` → `ExternalLeaseHostB`, two
// distinct types) exercises that decision the same way a re-host would.

#if canImport(AppKit)

import AppKit
import Foundation
import SwiftUI
import Testing

import MonetizationCore
import MonetizationTesting
@testable import MonetizationUI

@MainActor
@Suite("BannerSlotView — externally owned lease (#1080)", .timeLimit(.minutes(1)))
struct BannerSlotExternalLeaseTests {

    private func startedSession(provider: FakeAdProvider) async -> BannerSessionModel {
        let (gate, _) = SessionFixture.gate(SessionFixture.openState)
        let model = BannerSessionModel(adProvider: provider, adGate: gate, now: { SessionFixture.today })
        await model.start()
        return model
    }

    private func loadedHandleIDs(_ model: BannerSessionModel) -> Set<UUID> {
        Set(model.slots.values.compactMap { $0.loadedHandle?.id })
    }

    /// Mutation target (#1080, executed and reverted — see the dispatch
    /// report): in `BannerSlotRegistration.update()`, change
    /// `effective.attach(to: session)` to `ownLease.attach(to: session)`,
    /// ignoring the caller-supplied lease.
    @Test("T1: the same external lease survives its view being re-hosted under a new identity")
    func externalLeaseSurvivesReHost() async {
        let provider = FakeAdProvider()
        let session = await startedSession(provider: provider)
        let lease = BannerSlotLease()

        let host = NSHostingView(
            rootView: ExternalLeaseSwitcher(session: session, lease: lease, useFirstIdentity: true)
        )
        host.frame = CGRect(x: 0, y: 0, width: 320, height: 400)
        host.layoutSubtreeIfNeeded()

        #expect(await eventually { loadedHandleIDs(session).count == 1 })
        #expect(await provider.refreshCallCount == 1)
        #expect(session.slots.count == 1)
        let firstID = session.slots.keys.first
        let handles = loadedHandleIDs(session)

        // The re-host: a structurally different view type hosts the SAME
        // external lease, with no `.id(...)` bridging the two identities —
        // matching how `BannerAccessoryView`'s own identity is what changes
        // under `tabViewBottomAccessory`, not the lease it's handed.
        host.rootView = ExternalLeaseSwitcher(session: session, lease: lease, useFirstIdentity: false)
        host.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(300))

        #expect(await provider.refreshCallCount == 1, "the re-host must not re-request the banner")
        #expect(session.slots.count == 1, "the re-host must not register a second slot")
        #expect(session.slots.keys.first == firstID, "the re-host must keep the same slot id")
        #expect(loadedHandleIDs(session) == handles, "the re-host must keep the same loaded handle")
    }
}

// MARK: - Hosts

/// Two structurally distinct types (not the same type reused) so SwiftUI
/// treats them as different view identities — the same shape of change a
/// native re-host produces on `BannerAccessoryView`'s own identity.
private struct ExternalLeaseHostA: View {
    let session: BannerSessionModel
    let lease: BannerSlotLease

    var body: some View {
        BannerSlotView(lease: lease, isSuppressed: false)
            .environment(\.bannerSession, session)
    }
}

private struct ExternalLeaseHostB: View {
    let session: BannerSessionModel
    let lease: BannerSlotLease

    var body: some View {
        BannerSlotView(lease: lease, isSuppressed: false)
            .environment(\.bannerSession, session)
    }
}

private struct ExternalLeaseSwitcher: View {
    let session: BannerSessionModel
    let lease: BannerSlotLease
    let useFirstIdentity: Bool

    var body: some View {
        if useFirstIdentity {
            ExternalLeaseHostA(session: session, lease: lease)
        } else {
            ExternalLeaseHostB(session: session, lease: lease)
        }
    }
}

#endif
