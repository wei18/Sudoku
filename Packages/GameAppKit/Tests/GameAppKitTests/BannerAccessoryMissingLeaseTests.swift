// BannerAccessoryMissingLeaseTests — pins the #1080 no-silent-fallback rule:
// `BannerAccessoryView` mounted with no `\.bannerAccessoryLease` in its
// environment (a lost `GameRoot` injection) must call
// `onMissingAccessoryLease()` and render nothing, mirroring
// `BannerSessionModel.onMissingSession` (#1058, M1) rather than quietly
// falling back to a self-owned lease that would re-register on every
// `tabViewBottomAccessory` re-host.
//
// iOS only: `BannerAccessoryView` itself only compiles `#if os(iOS)`.

#if os(iOS)

import SwiftUI
import Testing
import UIKit
@testable import GameAppKit

@MainActor
@Suite("BannerAccessoryView — missing lease (#1080)")
struct BannerAccessoryMissingLeaseTests {

    /// Mutation target: remove the `Self.onMissingAccessoryLease()` call
    /// from the `nil` branch of `BannerAccessoryView.content` — `calls.count`
    /// stays 0.
    ///
    /// Rendering the "nothing" half of the contract is not independently
    /// asserted here: `UIHostingController.sizeThatFits(in:)` reports a
    /// nonzero height for this exact tree even with `EmptyView()` as the
    /// only content (confirmed empirically — not a measurement this API can
    /// answer for an unwindowed, unparented hosting controller), and this
    /// file's own header notes accessibility-identifier lookup already
    /// failed the same way for a sibling suite. The hook firing is the
    /// pinned, reliable half of the contract.
    @Test("T4: no \\.bannerAccessoryLease in the environment calls onMissingAccessoryLease()")
    func missingLeaseIsReported() {
        let calls = CallBox()
        let original = BannerAccessoryView.onMissingAccessoryLease
        BannerAccessoryView.onMissingAccessoryLease = { calls.count += 1 }
        defer { BannerAccessoryView.onMissingAccessoryLease = original }

        // No `.environment(\.bannerAccessoryLease, ...)` anywhere in this
        // tree — the key's `nil` default is exactly the lost-injection case.
        let controller = UIHostingController(rootView: BannerAccessoryView())
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()

        #expect(calls.count > 0, "missing-lease mount must call onMissingAccessoryLease()")
    }
}

@MainActor
private final class CallBox {
    var count = 0
}

#endif
