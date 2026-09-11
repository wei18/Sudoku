// BannerSlotColdLaunchTests — #1058: production incident regression coverage.
//
// `BannerSlotView.body` used to attach `.task { await resolveGateAndLoad() }`
// to a `Group` whose conditional content collapses to `EmptyView()` when
// `shouldShow` starts `nil` — the exact cold-launch condition (`shouldShow`
// is seeded from `AdGate.lastKnownShouldShowBanner`, which is `nil` before
// the session's first resolution). SwiftUI never runs a `.task` attached to
// a view that renders as `EmptyView`, so gate resolution never started: zero
// ad impressions, and the ATT primer (`onAdContext`) that only fires once
// the gate opens never presented either (C-33).
//
// iOS-only: adapts `GameAppKitTests/BannerAccessoryViewTests.swift`'s harness
// (same repo, `#if os(iOS)`, `UIHostingController` in a real `UIWindow`).
// That file's header documents WHY a real host is required: rendering a
// SwiftUI view whose `.task` performs a cross-actor-boundary `await` in a
// headless offscreen `NSWindow` under `swift test` never reliably pumps the
// run loop to resume it (`TodayTabHostTests`, four diagnostic rounds) — only
// a real iOS Simulator XCTest host's `UIApplication` run loop does. Run via
// `xcodebuild test -destination 'platform=iOS Simulator,...'`; a macOS
// `swift test` invocation structurally excludes this whole file.
//
// One deliberate difference from that file: `mount()` below wraps the view
// in a `VStack`, not a bare `UIHostingController` root. Verified empirically
// (temporarily reverting fix A) that the nesting is load-bearing — hosting
// `BannerSlotView` directly AS the root content mounts it unconditionally
// regardless of `Group`/`EmptyView`, masking the defect; nested one level
// inside a real parent container (`BannerSlotView`'s actual production
// position, always inside `TodayTabHost`'s `VStack`) it reproduces exactly.

#if os(iOS)

import Foundation
import SwiftUI
import Testing
import UIKit

import MonetizationCore
import MonetizationTesting
@testable import MonetizationUI

@MainActor
@Suite("BannerSlotView — cold-launch .task lifecycle (#1058)")
struct BannerSlotColdLaunchTests {

    /// Mounts `view` inside a real, key `UIWindow` — an unattached
    /// `UIHostingController`'s view never enters the window hierarchy, so
    /// SwiftUI never mounts its body and `.task` never fires at all,
    /// regardless of the fix under test. The `VStack` wrapper is NOT
    /// incidental: `BannerSlotView` is production is always nested inside a
    /// parent container (`TodayTabHost`'s `VStack`, never a bare hosting
    /// root) — verified empirically that this nesting is load-bearing for
    /// reproducing the defect. Hosting `BannerSlotView` directly as
    /// `UIHostingController`'s root content does NOT reproduce it (the root
    /// content gets mounted unconditionally regardless of `Group`/`EmptyView`
    /// content); nested one level inside a real parent it does, matching
    /// production exactly.
    private func mount(_ view: some View) -> UIWindow {
        let controller = UIHostingController(rootView: VStack { view })
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 80))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        return window
    }

    // MARK: - Test 1: gate resolution must actually start

    /// Fails loudly if `BannerSlotView`'s `.task` never runs. A fresh `AdGate`
    /// (never resolved this session) has `lastKnownShouldShowBanner == nil`
    /// — the exact production cold-launch condition that seeds `shouldShow`.
    /// The store's `loadCallCount` is the direct, outcome-independent proof
    /// that `resolveGateAndLoad` actually reached `AdGate.shouldShowBanner`
    /// (mirrors the issue's own NSLog-probe-before-the-gate-call diagnosis) —
    /// unlike asserting on the gate's DECISION, this can't pass by accident
    /// if the `.task` never mounted.
    @Test("cold launch: shouldShow starts nil, but gate resolution still starts")
    func gateResolutionStartsFromColdLaunch() async {
        let store = FakeAdGateStateStore(
            initial: AdGateState(firstLaunchAt: Date().addingTimeInterval(-30 * 86_400))
        )
        let gate = AdGate(store: store)
        #expect(gate.lastKnownShouldShowBanner == nil, "precondition: nothing resolved yet this session")

        let window = mount(BannerSlotView(adProvider: FakeAdProvider(), adGate: gate))

        var iterations = 0
        while await store.loadCallCount == 0, iterations < 300 {
            try? await Task.sleep(for: .milliseconds(10))
            iterations += 1
        }

        #expect(
            await store.loadCallCount > 0,
            "BannerSlotView's .task must call into AdGate.shouldShowBanner even when shouldShow starts nil"
        )
        _ = window // keep the window (and its retained controller) alive until here
    }

    // MARK: - Test 2: ATT primer before ad-context / ad-load, and consent before request

    private actor OrderLog {
        private(set) var events: [String] = []
        func record(_ event: String) { events.append(event) }
    }

    /// Records the moment `resolveGateAndLoad`'s reload step reaches the
    /// provider — i.e. the actual ad request.
    private struct RecordingAdProvider: AdProvider {
        let log: OrderLog
        func initialize() async throws {}
        func awaitReady() async throws {}
        var bannerStatus: AdBannerStatus { get async { .notInitialized } }
        func refreshBanner() async throws { await log.record("adLoadStarted") }
        func dispose(handle: AdBannerHandle) async {}
    }

    /// Pins two orderings at once with the REAL `BannerSlotView.body` (its
    /// actual `.task`, not a free function called directly):
    ///   1. the ATT primer hook (`onAdContext`) fires before any ad load
    ///      (C-33 — the primer must not be able to die silently again).
    ///   2. the ad load cannot start before the boot-completion signal fires
    ///      (#1058 fix B) — proving consent-before-request holds by
    ///      construction, not by timing luck. `bootSignal.markReady()` is
    ///      delayed on purpose so a wrong implementation (load gated on
    ///      mount instead of the signal) would race "adLoadStarted" ahead of
    ///      "bootReady".
    @Test("order: ATT primer, then boot completion, then ad load — never ad load first")
    func primerThenBootThenAdLoad() async {
        let log = OrderLog()
        let onAdContext: @Sendable () async -> Void = {
            await log.record("primerChecked")
        }
        let bootSignal = MonetizationBootSignal()
        let provider = RecordingAdProvider(log: log)
        // Gate OPEN: 30 days post-launch, not purchased, never dismissed.
        let gate = AdGate(store: FakeAdGateStateStore(
            initial: AdGateState(firstLaunchAt: Date().addingTimeInterval(-30 * 86_400))
        ))

        let window = mount(BannerSlotView(
            adProvider: provider,
            adGate: gate,
            onAdContext: onAdContext,
            bootSignal: bootSignal
        ))

        // Delay boot completion so a load that (wrongly) fires on mount
        // instead of on the signal would record "adLoadStarted" before
        // "bootReady" — the assertion below would then catch it. 500ms (not
        // a shorter value) verified necessary: with only 50ms, ambient
        // actor-hop / simulator scheduling latency in the reload chain
        // occasionally absorbed the whole margin even on unfixed code,
        // producing a false green.
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            await log.record("bootReady")
            await bootSignal.markReady()
        }

        var iterations = 0
        while await log.events.count < 3, iterations < 300 {
            try? await Task.sleep(for: .milliseconds(10))
            iterations += 1
        }

        let events = await log.events
        #expect(
            events == ["primerChecked", "bootReady", "adLoadStarted"],
            "ATT primer must fire before boot completes, and the ad load must never start before it"
        )
        _ = window
    }
}

#endif
