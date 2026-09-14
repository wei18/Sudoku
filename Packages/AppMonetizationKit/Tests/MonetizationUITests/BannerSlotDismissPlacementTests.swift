// BannerSlotDismissPlacementTests — #1084: the ✕ must never overlap the
// AdMob creative. AdMob policy forbids app content over or immediately
// adjacent to an ad, and a manual tap sweep hit the ad 2 times out of 9 taps
// on the old top-trailing overlay ✕.
//
// Measures the slot band, the creative, and the ✕ in one shared coordinate
// space via `BannerSlotGeometryKey` — an `anchorPreference` triple declared
// on `BannerSlotView` only for this test — and asserts the ✕ sits in the
// gutter past the creative's trailing edge, never on top of it, at three
// host widths: 402pt and 393pt (comfortable — full nominal padding on both,
// PM's final ruling, #1084) and 375pt (too narrow for the full nominal
// padding, so `BannerSlotBandLayout` shrinks it symmetrically instead of
// letting the ✕ run off-screen). The ruled constraint is "the ✕ stays fully
// on-screen", not "the ✕ stays inside the visible band" — 393pt's ✕ sits a
// few points past the band's own trailing edge but well inside the screen.

#if canImport(AppKit)

import AppKit
import Foundation
import SwiftUI
import Testing

import MonetizationCore
import MonetizationTesting
@testable import MonetizationUI

@MainActor
@Suite("BannerSlotView — ✕ placement outside the creative (#1084)", .timeLimit(.minutes(1)))
struct BannerSlotDismissPlacementTests {

    /// The nominal horizontal padding real callers pass (e.g. `BoardView`).
    private static let nominalPadding: CGFloat = 16

    private func loadedSession() async -> BannerSessionModel {
        let (gate, _) = SessionFixture.gate(SessionFixture.openState)
        let model = BannerSessionModel(adProvider: HostingAdProvider(), adGate: gate, now: { SessionFixture.today })
        await model.start()
        return model
    }

    /// Mounts a loaded `BannerSlotView` (with `horizontalPadding:
    /// nominalPadding`, exactly as a real caller would) inside a fixed-width
    /// host, and pumps the run loop until the geometry preference has
    /// resolved (mirrors `BoardViewBannerTests.settledBannerHeight` — the
    /// proven pattern for a headless `NSHostingView` waiting on an async
    /// provider load).
    private func measure(hostWidth: CGFloat, session: BannerSessionModel, passes: Int = 50) -> GeometryBox {
        let box = GeometryBox()
        let host = NSHostingView(
            rootView: GeometryHost(session: session, hostWidth: hostWidth, horizontalPadding: Self.nominalPadding, box: box)
        )
        host.frame = CGRect(x: 0, y: 0, width: hostWidth, height: 200)
        for _ in 0..<passes where box.creative == nil {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        host.layoutSubtreeIfNeeded()
        return box
    }

    /// Same polling pattern as `measure(hostWidth:session:passes:)`, but
    /// mounts `UnconstrainedWidthGeometryHost` (a horizontal `ScrollView`,
    /// proposing `.infinity` width — #1084 review fix 3) instead of a
    /// fixed-width host. A plain (non-`async`) function, like `measure`:
    /// `RunLoop.current.run(until:)` is unavailable from an async context.
    private func measureUnconstrained(session: BannerSessionModel, passes: Int = 50) -> GeometryBox {
        let box = GeometryBox()
        let host = NSHostingView(
            rootView: UnconstrainedWidthGeometryHost(session: session, horizontalPadding: Self.nominalPadding, box: box)
        )
        host.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        for _ in 0..<passes where box.creative == nil {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        host.layoutSubtreeIfNeeded()
        return box
    }

    @Test(
        "✕ is a 44×44 target that never overlaps the creative and never runs off the host",
        arguments: [402.0, 393.0, 375.0]
    )
    func dismissPlacement(hostWidth: CGFloat) async {
        let session = await loadedSession()
        let box = measure(hostWidth: hostWidth, session: session)

        guard let slot = box.slot, let creative = box.creative, let dismiss = box.dismiss else {
            let message: String = "geometry did not resolve at hostWidth \(hostWidth): "
                + "slot=\(String(describing: box.slot)) creative=\(String(describing: box.creative)) "
                + "dismiss=\(String(describing: box.dismiss))"
            Issue.record(Comment(rawValue: message))
            return
        }

        // True at all three widths (PM's final ruling, #1084): the
        // constraint `BannerSlotBandLayout` enforces is "the ✕ stays fully
        // on-screen", NOT "the ✕ stays inside the visible band" — so this
        // checks against `hostWidth` and `creative.maxX`, never `slot`.
        #expect(creative.size == BannerSlotView.creativeSize, "hostWidth \(hostWidth): creative \(creative)")
        #expect(creative.minX == slot.minX, "hostWidth \(hostWidth): creative \(creative) slot \(slot)")
        #expect(dismiss.width >= BannerSlotView.dismissTargetSize, "hostWidth \(hostWidth): ✕ \(dismiss)")
        #expect(dismiss.height >= BannerSlotView.dismissTargetSize, "hostWidth \(hostWidth): ✕ \(dismiss)")
        #expect(!dismiss.intersects(creative), "hostWidth \(hostWidth): ✕ \(dismiss) overlaps creative \(creative)")
        #expect(dismiss.minX >= creative.maxX, "hostWidth \(hostWidth): ✕ \(dismiss) starts before creative ends")
        #expect(dismiss.maxX <= hostWidth, "hostWidth \(hostWidth): ✕ \(dismiss) runs off the host")
        #expect(creative.minX >= 0, "hostWidth \(hostWidth): creative \(creative) starts off the host")

        switch hostWidth {
        case 402:
            // 402pt host, ≥ needed(364) + nominalPadding(16) = 380: the full
            // nominal 16pt padding, byte-identical to the geometry before
            // the narrow-width shrink rule existed.
            #expect(creative.minX == 16, "hostWidth 402: creative \(creative)")
            #expect(dismiss.maxX == 380, "hostWidth 402: ✕ \(dismiss)")
            // `.slot` is the padded-in band, not the Layout's full width —
            // a non-tautological check that it's neither a fixed marker
            // size nor the un-padded 402pt host width.
            #expect(
                rectApproximatelyEqual(slot, CGRect(x: 16, y: 0, width: 370, height: 50)),
                "hostWidth 402: slot \(slot)"
            )
        case 393:
            // 393pt — the most common iPhone width — is ALSO ≥ 380, so it
            // gets the SAME full 16pt padding as 402 (PM's final ruling,
            // #1084): no visible inconsistency between the two most common
            // widths. The ✕ ends 3pt past the band's own trailing edge
            // (16 + 361 = 377) but 13pt inside the screen (393) — the ruled
            // constraint is on-screen, not in-band.
            #expect(creative.minX == 16, "hostWidth 393: creative \(creative)")
            #expect(dismiss.maxX == 380, "hostWidth 393: ✕ \(dismiss)")
            #expect(
                rectApproximatelyEqual(slot, CGRect(x: 16, y: 0, width: 361, height: 50)),
                "hostWidth 393: slot \(slot)"
            )
        default:
            // 375pt host: 364 (creative + ✕) + 16 = 380 doesn't fit, so the
            // padding shrinks symmetrically to (375 − 364) / 2 = 5.5pt on
            // each side (PM ruling, #1084) instead of overflowing the host.
            #expect(abs(creative.minX - 5.5) < 0.01, "hostWidth 375: creative \(creative)")
            #expect(abs(dismiss.maxX - 369.5) < 0.01, "hostWidth 375: ✕ \(dismiss)")
            #expect(
                rectApproximatelyEqual(slot, CGRect(x: 5.5, y: 0, width: 364, height: 50)),
                "hostWidth 375: slot \(slot)"
            )
        }
    }

    /// #1084 review fix 3, end-to-end via a real view hierarchy: an
    /// unconstrained width proposal must still resolve to a concrete,
    /// finite geometry, not `.infinity`/`NaN`.
    ///
    /// Both `.fixedSize(horizontal:vertical:)` and `ScrollView(.horizontal)`
    /// were tried as the "give an unconstrained proposal" host, per the
    /// brief. Neither actually feeds a literal `.infinity` width to
    /// `BannerSlotBandLayout.sizeThatFits` in this headless macOS
    /// `NSHostingView` harness — a debug print at the call site showed
    /// `ScrollView(.horizontal)` proposing `nil` then a concrete resolved
    /// value (never `.infinity`), so a mutation reverting the `.infinity`
    /// clamp stays GREEN here; it's a false-negative test for that specific
    /// case. `ScrollView(.horizontal)` is kept anyway since it's a
    /// legitimate, useful check that the `nil` path resolves correctly
    /// end-to-end through the real view/anchor-preference machinery. The
    /// `.infinity` clamp itself is unit-tested directly below, against the
    /// extracted `resolvedBannerBandWidth` free function, since no view
    /// hierarchy available in this harness can produce that input.
    @Test("an unconstrained (nil) width proposal, e.g. inside a horizontal ScrollView, still reports a finite ideal size (#1084)")
    func dismissPlacementUnconstrainedWidth() async {
        let session = await loadedSession()
        let box = measureUnconstrained(session: session)

        guard let slot = box.slot, let creative = box.creative, let dismiss = box.dismiss else {
            Issue.record(Comment(rawValue: "geometry did not resolve under an unconstrained width proposal"))
            return
        }

        for (name, rect) in [("slot", slot), ("creative", creative), ("dismiss", dismiss)] {
            #expect(rect.width.isFinite, "\(name) width is not finite: \(rect)")
            #expect(rect.height.isFinite, "\(name) height is not finite: \(rect)")
        }

        // The ideal width (`needed + 2×nominalPadding` = 364 + 32 = 396)
        // gives the full nominal 16pt padding on both sides — same numbers
        // as the comfortable 402pt/393pt cases above.
        #expect(creative.minX == 16, "creative \(creative)")
        #expect(dismiss.maxX == 380, "✕ \(dismiss)")
        #expect(
            rectApproximatelyEqual(slot, CGRect(x: 16, y: 0, width: 364, height: 50)),
            "slot \(slot)"
        )
    }

    /// #1084 review fix 3, direct: `resolvedBannerBandWidth` must clamp a
    /// literal `.infinity` (and `.nan`) proposal to `ideal`, not propagate
    /// it — the scenario no view hierarchy in this test target can actually
    /// produce (see `dismissPlacementUnconstrainedWidth`'s doc comment).
    @Test("resolvedBannerBandWidth clamps nil, infinite, and NaN proposals to the ideal width, and passes finite ones through (#1084)")
    func resolvedBannerBandWidthClampsNonFiniteProposals() {
        #expect(resolvedBannerBandWidth(proposal: nil, ideal: 396) == 396)
        #expect(resolvedBannerBandWidth(proposal: .infinity, ideal: 396) == 396)
        #expect(resolvedBannerBandWidth(proposal: -.infinity, ideal: 396) == 396)
        #expect(resolvedBannerBandWidth(proposal: .nan, ideal: 396) == 396)
        #expect(resolvedBannerBandWidth(proposal: 402, ideal: 396) == 402)
    }
}

/// Component-wise `CGRect` equality within `tolerance` — avoids float
/// round-off false negatives on the 5.5pt narrow-width case.
private func rectApproximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 0.01) -> Bool {
    abs(lhs.minX - rhs.minX) < tolerance
        && abs(lhs.minY - rhs.minY) < tolerance
        && abs(lhs.width - rhs.width) < tolerance
        && abs(lhs.height - rhs.height) < tolerance
}

// MARK: - Geometry harness

@MainActor
private final class GeometryBox {
    var slot: CGRect?
    var creative: CGRect?
    var dismiss: CGRect?

    func record(anchors: [BannerSlotGeometryPart: Anchor<CGRect>], in proxy: GeometryProxy) -> Color {
        if let anchor = anchors[.slot] { slot = proxy[anchor] }
        if let anchor = anchors[.creative] { creative = proxy[anchor] }
        if let anchor = anchors[.dismiss] { dismiss = proxy[anchor] }
        return .clear
    }
}

/// A loaded `BannerSlotView` filling a fixed-width host — the same
/// coordinate space every measured part is read back in. `horizontalPadding`
/// goes straight into `BannerSlotView.init`, exactly as a real caller (e.g.
/// `BoardView`) would pass it, so `BannerSlotBandLayout` receives the host's
/// FULL width and owns the narrow-width symmetric shrink itself (#1084) —
/// there's no separate `.padding()` wrapper here.
private struct GeometryHost: View {
    let session: BannerSessionModel
    let hostWidth: CGFloat
    let horizontalPadding: CGFloat
    let box: GeometryBox

    var body: some View {
        BannerSlotView(isSuppressed: false, horizontalPadding: horizontalPadding)
            .frame(width: hostWidth)
            .environment(\.bannerSession, session)
            // A headless `NSHostingView` defaults to `displayScale` 1 (no
            // real screen backing), which pixel-snaps a placed 5.5pt origin
            // to 6pt. Every real device this 375pt-host shape targets is
            // @2x, where 5.5pt lands exactly on a pixel (11px) — @2x here
            // matches that and lets the narrow-width case measure the true
            // un-rounded layout value (#1084).
            .environment(\.displayScale, 2)
            .overlayPreferenceValue(BannerSlotGeometryKey.self) { anchors in
                GeometryReader { proxy in
                    box.record(anchors: anchors, in: proxy)
                }
            }
    }
}

/// A loaded `BannerSlotView` inside a horizontal `ScrollView`, which proposes
/// literal `.infinity` width to its content along the scroll axis (#1084
/// review fix 3) — reproduces the unconstrained-width proposal
/// `BannerSlotBandLayout.sizeThatFits` must clamp instead of propagating.
private struct UnconstrainedWidthGeometryHost: View {
    let session: BannerSessionModel
    let horizontalPadding: CGFloat
    let box: GeometryBox

    var body: some View {
        ScrollView(.horizontal) {
            BannerSlotView(isSuppressed: false, horizontalPadding: horizontalPadding)
                .environment(\.bannerSession, session)
                .environment(\.displayScale, 2)
                .overlayPreferenceValue(BannerSlotGeometryKey.self) { anchors in
                    GeometryReader { proxy in
                        box.record(anchors: anchors, in: proxy)
                    }
                }
        }
    }
}

#endif
