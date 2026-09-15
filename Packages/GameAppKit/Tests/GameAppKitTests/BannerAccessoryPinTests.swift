// BannerAccessoryPinTests — pin test for the shared banner accessory (#1080).
//
// PM requirement: the accessory's pre-#1080-merge render-level test suite
// (deleted during the #1062 rebase — see
// meetings/2026-09-07_1024-banner-accessory.impl-notes.md's "#1080
// follow-through") needed a replacement pin — an E2E-only pin does not
// count. This suite renders the REAL `RootShellView` hosting the REAL
// `BannerAccessoryView` on top of a started `BannerSessionModel` and proves,
// at the render level:
//
//   (a) gate open   → the accessory renders a registered slot in
//       `.loading`/`.loaded` state, not an empty capsule, and the
//       `\.bannerSession` injection actually reaches the slot (no
//       `onMissingSession` fallback).
//   (b) gate denied → no accessory container at all (or a zero-height one
//       with no registered slot) — `isEnabled: false` suppresses the WHOLE
//       capsule, not just its content.
//   (c) macOS       → `makeBottomAccessory()` returns `EmptyView`,
//       STRUCTURALLY: `BannerAccessoryView` does not compile into the macOS
//       binary at all (mirrors GameShellKit's
//       `RootShellViewBottomAccessoryRenderTests`, which cannot even be
//       compiled on macOS for the same reason).
//
// Each `@Test`'s doc comment names the exact mutation that turns it red.

#if os(macOS)

import SwiftUI
import Testing
@testable import GameAppKit

@MainActor
@Suite("Banner accessory pin (#1080)")
struct BannerAccessoryPinTests {

    @Test("(c) macOS: makeBottomAccessory() is structurally EmptyView")
    func macOSAccessoryIsStructurallyEmpty() {
        // Mutation: remove the `#if os(iOS)` guard inside `makeBottomAccessory`
        // (MakeGameApp+Helpers.swift) so both branches construct
        // `BannerAccessoryView()`. On macOS that mutation doesn't just make
        // this test red — `BannerAccessoryView` (and the `BannerSlotView` it
        // wraps) is itself gated `#if os(iOS)`, so the type doesn't exist on
        // this platform at all and the macOS build fails outright. That
        // build failure IS the structural exclusion this test stands in for.
        #expect((makeBottomAccessory() as Any) is EmptyView)
    }
}

#endif

#if os(iOS)

import Foundation
import SwiftUI
import Testing
import UIKit
import MonetizationCore
import MonetizationUI
import MonetizationTesting
import GameShellUI
@testable import GameAppKit

// MARK: - Sentinel route/factory
//
// A private copy, not shared with GameShellKit's
// `RootShellViewBottomAccessoryRenderTests` — per instruction, GameShellKit's
// test helpers stay test-only and unshared across packages.

private enum AccessoryPinSentinelRoute: Hashable {
    case first
    case settings
}

private struct AccessoryPinSentinelFactory: RouteFactory {
    typealias Route = AccessoryPinSentinelRoute

    @MainActor
    func view(for route: AccessoryPinSentinelRoute, path: Binding<[AccessoryPinSentinelRoute]>?) -> AnyView {
        AnyView(Text("destination"))
    }
}

// MARK: - Container-walking helpers
//
// Private copies of GameShellKit's `findAccessoryContainer` /
// `waitForAccessoryContainer` (RootShellViewBottomAccessoryRenderTests.swift)
// — same proof strategy (SwiftUI mounts `tabViewBottomAccessory`'s content
// inside a private container view whose class name contains
// "BottomAccessory"), not exported across packages.

@MainActor
private func findAccessoryContainer(in view: UIView) -> UIView? {
    if String(describing: type(of: view)).contains("BottomAccessory") {
        return view
    }
    for subview in view.subviews {
        if let found = findAccessoryContainer(in: subview) {
            return found
        }
    }
    return nil
}

@MainActor
private func waitForAccessoryContainer(in window: UIWindow) async -> UIView? {
    var iterations = 0
    while iterations < 50 {
        if let container = findAccessoryContainer(in: window) {
            return container
        }
        try? await Task.sleep(for: .milliseconds(20))
        iterations += 1
    }
    return nil
}

/// Polls `condition` every 10ms until it holds or `timeout` elapses (mirrors
/// `TodayTabHostTests.eventually`).
@MainActor
private func eventually(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        if ContinuousClock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

// MARK: - Session + hosted-shell helpers

/// A `BannerSessionModel` whose gate is open or denied, already `start()`ed.
/// Denied via `hasPurchasedRemoveAds` — the highest-precedence, `now`-independent
/// `AdGate` rule (`AdGate.swift` resolution order, rule 1).
@MainActor
private func makeStartedSession(gateOpen: Bool) async -> BannerSessionModel {
    let state = AdGateState(
        firstLaunchAt: Date(timeIntervalSince1970: 0),
        hasPurchasedRemoveAds: !gateOpen
    )
    let adGate = AdGate(store: FakeAdGateStateStore(initial: state))
    let session = BannerSessionModel(adProvider: FakeAdProvider(), adGate: adGate)
    await session.start()
    return session
}

/// Hosts the REAL `RootShellView` + REAL `BannerAccessoryView`, wired to
/// `session` through `\.bannerSession` and `bottomAccessoryIsEnabled:
/// session.isVisible` — the exact same wiring `makeGameAppCore` uses
/// (`MakeGameApp.swift`'s `GameRoot(bannerSession:...)` +
/// `bottomAccessory: { makeBottomAccessory() }`).
@MainActor
private func makeHostedShell(session: BannerSessionModel) -> UIWindow {
    let shell = RootShellView<AccessoryPinSentinelRoute, Text, AnyView>(
        selectedTab: .constant(.today),
        path: { _ in .constant([]) },
        routeFactory: AccessoryPinSentinelFactory(),
        settingsRoute: .settings,
        tabRoot: { tab in Text(tab.rawValue) },
        bottomAccessoryIsEnabled: session.isVisible,
        bottomAccessory: { AnyView(BannerAccessoryView()) }
    )
    .environment(\.bannerSession, session)

    let controller = UIHostingController(rootView: shell)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    window.layoutIfNeeded()
    return window
}

// MARK: - Suite
//
// `.serialized`: test (a) temporarily swaps the static
// `BannerSessionModel.onMissingSession` hook to observe it, then restores
// the original — that mutable static must not race a concurrently-running
// test in this suite.

@MainActor
@Suite("Banner accessory pin (#1080)", .serialized)
struct BannerAccessoryPinTests {

    @Test("(a) gate open: accessory renders a registered, loading-or-loaded slot")
    func gateOpenRendersRegisteredSlot() async {
        let session = await makeStartedSession(gateOpen: true)
        #expect(session.isVisible, "precondition: an open gate must resolve to a visible session before this test proves anything about rendering")

        // Prove the `\.bannerSession` injection actually reaches the slot —
        // mutation (a2): dropping `.environment(\.bannerSession, session)`
        // from `makeHostedShell` would make `BannerSlotRegistration` call
        // `onMissingSession()` instead of registering. Swap + restore the
        // static hook around the render.
        let originalOnMissingSession = BannerSessionModel.onMissingSession
        var missingSessionCalled = false
        BannerSessionModel.onMissingSession = { missingSessionCalled = true }
        defer { BannerSessionModel.onMissingSession = originalOnMissingSession }

        let window = makeHostedShell(session: session)
        let container = await waitForAccessoryContainer(in: window)

        #expect(
            !missingSessionCalled,
            "mutation (a2): the \\.bannerSession injection was dropped — the slot fell back to onMissingSession()"
        )

        guard let container else {
            Issue.record("no tabViewBottomAccessory container ever appeared — mutation (a1): BannerAccessoryView.body was reverted to EmptyView()")
            return
        }
        #expect(!container.subviews.isEmpty, "accessory container is empty — mutation (a1): BannerAccessoryView.body was reverted to EmptyView()")

        let registered = await eventually { session.slots.count == 1 }
        #expect(
            registered,
            "expected exactly one registered slot — the accessory's BannerSlotView never registered (currently: \(session.slots.count))"
        )

        if let status = session.slots.values.first {
            let isLoadingOrLoaded: Bool
            switch status {
            case .loading, .loaded: isLoadingOrLoaded = true
            default: isLoadingOrLoaded = false
            }
            #expect(isLoadingOrLoaded, "registered slot's status is neither .loading nor .loaded — got \(status)")
        }
    }

    @Test("(b) gate denied: no accessory capsule and no registered slot")
    func gateDeniedRendersNothing() async {
        let session = await makeStartedSession(gateOpen: false)
        #expect(!session.isVisible, "precondition: a denied gate must resolve to an invisible session before this test proves anything about suppression")

        let window = makeHostedShell(session: session)
        _ = await waitForAccessoryContainer(in: window)
        let container = findAccessoryContainer(in: window)

        // Mutation (b): `RootShellView.body`'s `isEnabled:` hardcoded to
        // `true` — the pre-#1079 empty-capsule regression: a container would
        // reappear with non-zero height even though nothing loaded into it.
        #expect(
            container == nil || (container!.bounds.height == 0 && container!.subviews.isEmpty),
            "isEnabled:false still drew a non-empty/non-zero-height container — mutation (b): isEnabled: hardcoded true"
        )
        #expect(session.slots.isEmpty, "no slot should hold load state while the accessory never mounted a visible BannerSlotView")
    }
}

#endif
