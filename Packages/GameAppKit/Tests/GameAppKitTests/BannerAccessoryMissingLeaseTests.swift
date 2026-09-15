// BannerAccessoryMissingLeaseTests — pins the #1080 no-silent-fallback rule:
// `BannerAccessoryView` mounted with no `\.bannerAccessoryLease` in its
// environment (a lost `GameRoot` injection) must call
// `onMissingAccessoryLease()` and register/load NOTHING with the session,
// mirroring `BannerSessionModel.onMissingSession` (#1058, M1) rather than
// quietly falling back to a self-owned lease that would re-register on
// every `tabViewBottomAccessory` re-host.
//
// iOS only: `BannerAccessoryView` itself only compiles `#if os(iOS)`.

#if os(iOS)

import Foundation
import SwiftUI
import Testing
import UIKit
import MonetizationCore
import MonetizationUI
import MonetizationTesting
@testable import GameAppKit

/// A started, gate-open `BannerSessionModel` over `provider` — if the
/// missing-lease branch ever regressed to a self-owned-lease fallback, this
/// is the session it would (wrongly) register and load against.
@MainActor
private func makeOpenStartedSession(provider: FakeAdProvider) async -> BannerSessionModel {
    let state = AdGateState(firstLaunchAt: Date(timeIntervalSince1970: 0))
    let adGate = AdGate(store: FakeAdGateStateStore(initial: state))
    let session = BannerSessionModel(adProvider: provider, adGate: adGate)
    await session.start()
    return session
}

/// Polls `condition` every 10ms until it holds or `timeout` elapses (mirrors
/// `BannerAccessoryPinTests.eventually`).
@MainActor
private func eventually(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        if ContinuousClock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

// `.serialized`: the test swaps the static `BannerAccessoryView
// .onMissingAccessoryLease` hook to observe it, then restores the
// original — that mutable static must not race a concurrently-running test
// in this suite (mirrors `BannerAccessoryPinTests`'s own `.serialized`).
@MainActor
@Suite("BannerAccessoryView — missing lease (#1080)", .serialized)
struct BannerAccessoryMissingLeaseTests {

    /// Mutation target: in `BannerAccessoryView.content`'s `nil` branch,
    /// render the self-owned-lease `BannerSlotView(isSuppressed:...)` AFTER
    /// the `Self.onMissingAccessoryLease()` call — the hook still fires, but
    /// `session.slots` stops being empty and `refreshCallCount` goes to 1.
    /// This is what makes the test pin "no fallback", not just "hook fired":
    /// a prior version of this test only asserted `calls.count > 0`, which
    /// stays green even with a silent fallback re-added next to the call.
    @Test("T4: no \\.bannerAccessoryLease reports it and registers/loads nothing (no fallback)")
    func missingLeaseReportsAndRegistersNothing() async {
        let provider = FakeAdProvider()
        let session = await makeOpenStartedSession(provider: provider)
        #expect(session.isVisible, "precondition: gate must be open for a fallback slot to ever register")

        let calls = CallBox()
        let original = BannerAccessoryView.onMissingAccessoryLease
        BannerAccessoryView.onMissingAccessoryLease = { calls.count += 1 }
        defer { BannerAccessoryView.onMissingAccessoryLease = original }

        // `\.bannerSession` IS injected (a fallback slot would find a real
        // session to register with) — only `\.bannerAccessoryLease` is
        // missing, the exact lost-injection case.
        let root = BannerAccessoryView().environment(\.bannerSession, session)
        let controller = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()

        let called = await eventually(timeout: .seconds(1.5)) { calls.count > 0 }
        #expect(called, "missing-lease mount must call onMissingAccessoryLease()")

        // Bounded settle past the hook firing — a fallback slot's register +
        // load both run asynchronously, so a load in flight at the moment
        // the hook fires would not yet show up in `session.slots`.
        try? await Task.sleep(for: .seconds(1))

        #expect(session.slots.isEmpty, "no fallback: nothing should register with the session (currently: \(session.slots.count) slot(s))")
        #expect(await provider.refreshCallCount == 0, "no fallback: nothing should request a banner")
    }
}

@MainActor
private final class CallBox {
    var count = 0
}

#endif
