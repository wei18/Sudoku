// BannerSlotCollapsedHeightTests — a hidden `BannerSlotView` contributes zero
// size, for every production host's padding (#1058 review follow-up).
//
// Hosts pass their inset as `horizontalPadding` / `verticalPadding` instead of
// chaining `.padding` onto the slot, because the slot applies it only to the
// visible banner. A `.padding` chained onto a hidden slot would render as a
// permanent dead gap (for a Remove-Ads purchaser, forever). This suite pins
// that a gate-denied slot measures 0pt with each host's real arguments.
//
// Rows are audited from `rg -n "BannerSlotView\(" Packages/*/Sources`:
//   - `GameAppKit.TodayTabHost.bannerSlot` (Today tab, both apps): 16 / 12.
//   - Sudoku `LiveRouteFactory.themedBanner()` and Minesweeper
//     `LiveRouteFactory.bannerSlot()` (Practice + Settings): 16 / 12.
//   - Sudoku `BoardView+Layout.themedBanner(horizontalPadding:)` and
//     Minesweeper `MinesweeperBoardView.bannerSlot(horizontalPadding:)`:
//     `theme.spacing.medium` on the compact layout (16 — both themes use
//     `SpacingTokens()`), 0 on the regular layout; no vertical padding.
// AppMonetizationKit cannot import the host modules, so the rows carry the
// literal values; the hosts' own snapshot suites pin that they pass them.

#if canImport(AppKit)

import AppKit
import Foundation
import SwiftUI
import Testing

import MonetizationCore
import MonetizationTesting
@testable import MonetizationUI

@MainActor
@Suite("BannerSlotView — collapsed state contributes zero height (#1058)")
struct BannerSlotCollapsedHeightTests {

    /// One production host's `BannerSlotView` padding wiring. Not `private` —
    /// the `@Test(arguments:)` macro expansion references this type from
    /// outside the suite's private scope.
    struct HostPadding: Sendable, CustomStringConvertible {
        let name: String
        let horizontal: CGFloat
        let vertical: CGFloat
        var description: String { name }
    }

    /// `nonisolated` (not the suite's own `@MainActor`): `@Test(arguments:)`
    /// evaluates this at test-discovery time, outside MainActor isolation.
    nonisolated static let productionHosts: [HostPadding] = [
        HostPadding(name: "TodayTabHost (Today tab, both apps)", horizontal: 16, vertical: 12),
        HostPadding(name: "Sudoku LiveRouteFactory.themedBanner (Practice, Settings)", horizontal: 16, vertical: 12),
        HostPadding(name: "Minesweeper LiveRouteFactory.bannerSlot (Practice, Settings)", horizontal: 16, vertical: 12),
        HostPadding(name: "Sudoku Board compact (BoardView+Layout.themedBanner)", horizontal: 16, vertical: 0),
        HostPadding(name: "Sudoku Board regular (BoardView+Layout.themedBanner)", horizontal: 0, vertical: 0),
        HostPadding(name: "Minesweeper Board compact (MinesweeperBoardView.bannerSlot)", horizontal: 16, vertical: 0),
        HostPadding(name: "Minesweeper Board regular (MinesweeperBoardView.bannerSlot)", horizontal: 0, vertical: 0),
    ]

    /// Renders through a real `NSHostingView` (the same AppKit-hosted path this
    /// repo's other layout-measurement tests use) and reads back its
    /// AutoLayout-derived intrinsic size at a fixed proposed width.
    private func measuredSize(of view: some View) -> CGSize {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 320, height: 1_000)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    private func startedSession(_ state: AdGateState, provider: FakeAdProvider) async -> BannerSessionModel {
        let (gate, _) = SessionFixture.gate(state)
        let session = BannerSessionModel(adProvider: provider, adGate: gate, now: { SessionFixture.today })
        await session.start()
        return session
    }

    @Test(
        "a gate-denied BannerSlotView contributes zero height, for every production host's padding",
        arguments: productionHosts
    )
    func collapsedContributesZeroHeight(host: HostPadding) async {
        let session = await startedSession(
            AdGateState(firstLaunchAt: SessionFixture.firstLaunch, hasPurchasedRemoveAds: true),
            provider: FakeAdProvider()
        )
        #expect(session.shouldShow == false)
        let view = BannerSlotView(
            isSuppressed: false,
            horizontalPadding: host.horizontal,
            verticalPadding: host.vertical
        )
        .environment(\.bannerSession, session)
        let size = measuredSize(of: view)
        #expect(
            size.height == 0,
            "\(host.name): a gate-denied BannerSlotView must contribute zero height to its parent, got \(size.height)pt"
        )
    }

    /// Sanity check on the measurement mechanism itself: with the same 16/12
    /// padding, a gate-open slot must measure non-zero. Without this, a
    /// `measuredSize` regression that always returns 0 would make every row
    /// above pass for the wrong reason.
    @Test("sanity: a gate-allowed BannerSlotView measures non-zero height with the same harness")
    func visibleMeasuresNonZeroHeight() async {
        let session = await startedSession(SessionFixture.openState, provider: FakeAdProvider(readinessHeld: true))
        let view = BannerSlotView(isSuppressed: false, horizontalPadding: 16, verticalPadding: 12)
            .environment(\.bannerSession, session)
        let size = measuredSize(of: view)
        #expect(size.height > 0, "measurement harness must report non-zero height for a visible banner, got \(size.height)pt")
    }
}

#endif
