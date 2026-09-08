// RootShellViewBottomAccessoryRenderTests — #1024 PM ruling (2026-09-08): the
// #1029 B-6 spike already proved AdMob-in-`tabViewBottomAccessory` works as an
// API; that is not proof OUR wiring (`RootShellView`'s generic `bottomAccessory`
// param → `.tabViewBottomAccessory { bottomAccessory() }`, RootShellView.swift)
// actually threads a caller's content through. This suite renders the REAL
// shell with a sentinel accessory and asserts it lands in the live view
// hierarchy — no monetization types, GameShellKit stays zero-dep.
//
// iOS-only, like `GameAppKit.BannerAccessoryViewTests`: `tabViewBottomAccessory`
// doesn't exist on macOS (design.md §2.4.1), and a macOS `swift test` host has
// no `UIApplication` run loop to mount a `UIHostingController` in anyway.
//
// Proof strategy (why NOT an accessibility-identifier lookup): tried first,
// empirically dead end. `.accessibilityIdentifier(_:)` on plain content
// (`Text`) does not surface through the public `UIAccessibilityIdentification`
// protocol OR the `UIAccessibilityContainer` count/index methods on any view
// in this hierarchy when walked in-process in a headless XCTest host — both
// came back empty on every ancestor, confirmed via `-recursiveDescription`
// (SwiftUI's real accessibility tree is built by the OS Accessibility
// server, not by calling these NSObject methods directly). What
// `-recursiveDescription` DOES show reliably: SwiftUI mounts
// `tabViewBottomAccessory`'s content inside a private container view whose
// class name contains "BottomAccessory" (`UIKit._UITabAccessoryContainer` →
// `SwiftUI.UIKitTabBarBottomAccessory` → the accessory's own rendered
// content, e.g. `SwiftUI.CGDrawingView` for `Text`). This suite proves
// wiring by container PRESENCE + non-empty CONTENT, contrasted against an
// `EmptyView` accessory to rule out "the container always has stray
// children regardless of what we pass" as a false-positive explanation.

#if os(iOS)

import SwiftUI
import Testing
import UIKit
@testable import GameShellUI

// MARK: - Sentinel route/factory (mirrors RootShellViewGenericityTests' shape)

private enum AccessoryRenderSentinelRoute: Hashable {
    case first
    case settings
}

private struct AccessoryRenderSentinelFactory: RouteFactory {
    typealias Route = AccessoryRenderSentinelRoute

    @MainActor
    func view(for route: AccessoryRenderSentinelRoute, path: Binding<[AccessoryRenderSentinelRoute]>?) -> AnyView {
        AnyView(Text("destination"))
    }
}

@MainActor
private func makeHostedShell(
    @ViewBuilder bottomAccessory: @escaping () -> AnyView
) -> UIWindow {
    let shell = RootShellView<AccessoryRenderSentinelRoute, Text, AnyView>(
        selectedTab: .constant(.today),
        path: { _ in .constant([]) },
        routeFactory: AccessoryRenderSentinelFactory(),
        settingsRoute: .settings,
        tabRoot: { tab in Text(tab.rawValue) },
        bottomAccessory: bottomAccessory
    )
    let controller = UIHostingController(rootView: shell)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    window.layoutIfNeeded()
    return window
}

/// Recursively finds SwiftUI's `tabViewBottomAccessory` container — see the
/// file header for how this was derived and why it is the proof strategy.
/// `@MainActor`: `UIView` is main-thread-only; without this, the polling
/// loop below resumes off-main after `Task.sleep` and trips the Main Thread
/// Checker on `.subviews`.
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

/// Bounded settle — SwiftUI's own content inside the accessory (a `Text`'s
/// `CGDrawingView`, say) is not necessarily present on the very first
/// `layoutIfNeeded()`; poll briefly rather than assume a fixed number of
/// run-loop turns is enough.
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

// MARK: - Suite

@MainActor
@Suite("RootShellView — tabViewBottomAccessory wiring actually renders (#1024)")
struct RootShellViewBottomAccessoryRenderTests {

    @Test("a non-EmptyView bottomAccessory is mounted with real content in the live hierarchy")
    func sentinelAccessoryRendersInHierarchy() async {
        let window = makeHostedShell {
            AnyView(
                Text("SENTINEL")
                    .frame(width: 111, height: 22)
                    .background(Color.red)
            )
        }

        let container = await waitForAccessoryContainer(in: window)

        guard let container else {
            Issue.record("no tabViewBottomAccessory container ever appeared — RootShellView's #if os(iOS) attach point is broken")
            return
        }
        #expect(
            !container.subviews.isEmpty,
            "tabViewBottomAccessory container exists but is empty — bottomAccessory's content never made it inside"
        )
    }

    @Test("an EmptyView bottomAccessory leaves the container empty (contrast case)")
    func emptyAccessoryLeavesContainerEmpty() async {
        let window = makeHostedShell { AnyView(EmptyView()) }

        // Same bounded settle as the sentinel case, but we EXPECT no
        // meaningful content to ever show up — poll once for a container,
        // then confirm whatever exists (container present or not at all)
        // carries no rendered subview, ruling out "the container always has
        // stray children" as an alternate explanation for the sentinel test
        // passing above.
        _ = await waitForAccessoryContainer(in: window)
        let container = findAccessoryContainer(in: window)

        #expect(
            container?.subviews.isEmpty ?? true,
            "EmptyView bottomAccessory produced a non-empty container — the sentinel test's pass is not proof of real wiring"
        )
    }
}

#endif
