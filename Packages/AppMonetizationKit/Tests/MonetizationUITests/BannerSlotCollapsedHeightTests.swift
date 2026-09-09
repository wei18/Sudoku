// BannerSlotCollapsedHeightTests — #1058 review follow-up (PM addition).
//
// The `.task` cold-launch fix (`BannerSlotColdLaunchTests.swift`) swapped
// `BannerSlotView`'s outer container from `Group` to `ZStack` so a `.task`
// attached to it always mounts. That container swap had an unintended side
// effect, caught by a code reviewer via an unrelated snapshot diff, not by
// any dedicated test: three hosts (`TodayTabHost`, and — through the shared
// `GameShellUI.PracticeHubShellView` / `SettingsKit.SettingsShellView` —
// both apps' Practice and Settings screens) chain
// `.padding(.horizontal:).padding(.vertical:)` onto the WHOLE
// `BannerSlotView` value and rely on it collapsing to true zero size when
// hidden (`VStack(spacing: 0)`, explicitly documented at each host as
// "zero-gap chrome seam ... not a spacing decision"). That collapse used to
// happen for free: a value that is STATICALLY `EmptyView`-typed (only
// reachable through `Group`'s transparent, type-preserving pass-through)
// lets an external `.padding()` collapse right along with it. `ZStack`
// breaks that optimization — the value is concrete and non-`EmptyView`-typed
// even when its rendered content is empty — so the external padding
// rendered for real, silently inserting a permanent dead gap above the tab
// bar for a gate-denied banner (e.g. every Remove-Ads purchaser, forever).
//
// Fix (`BannerSlotView.swift`): `horizontalPadding`/`verticalPadding` moved
// INSIDE `BannerSlotView`, applied only within the visible `banner` branch —
// so the 0pt-when-hidden contract is self-contained inside the one shared
// type every host routes through, independent of the outer container.
//
// This suite pins that contract directly and loudly, parameterized across
// EVERY production host's actual padding configuration (PM: a Today-only
// test leaves the identical bug reachable through the other doors). Board
// (both apps) is included for completeness even though its surrounding
// `VStack` uses a fixed NONZERO spacing token regardless of the banner's
// internal shown/hidden state (its `if let adProvider, let adGate` gate
// lives OUTSIDE `BannerSlotView`, at the host's own builder level, so Board
// was never part of the collapse-contract fix, and its own inline padding —
// horizontal-only — is unconditional, not reactive to the gate) — so Board's
// row exercises `BannerSlotView` with its actual (zero) padding arguments as
// a completeness check, not because Board depends on this contract.
//
// Scope note: measured here is `BannerSlotView`'s OWN contribution — the one
// shared implementation every host embeds — using each host's real
// production `horizontalPadding`/`verticalPadding` arguments (audited via
// `grep -rn "BannerSlotView(" Packages/*/Sources`, five call sites, both
// apps: `TodayTabHost.swift`, `LiveRouteFactory.swift` (Sudoku, Practice/
// Settings, and `BoardView+Layout.swift`'s `themedBanner`),
// `LiveRouteFactory+Helpers.swift` (Minesweeper, Practice/Settings), and
// `MinesweeperBoardView.swift`). `AppMonetizationKit` cannot import
// SudokuUI/MinesweeperUI/GameAppKit (they depend on it, not the reverse), so
// this cannot mount the literal `TodayTabHost` type — the existing snapshot
// suites (`TodayTabViewTests`, `MinesweeperTodayTabViewTests`, both
// confirmed passing byte-identical against their UNCHANGED committed
// baselines after this fix) are the integration-level proof that each host
// actually wires the values this suite pins.

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

    /// One production host's `BannerSlotView` padding wiring, audited from
    /// source (see file header for the exact `grep`). Not `private` — the
    /// `@Test(arguments:)` macro expansion references this type from
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
        HostPadding(name: "Practice hub banner (GameShellUI.PracticeHubShellView, both apps)", horizontal: 16, vertical: 12),
        HostPadding(name: "Settings banner (SettingsKit.SettingsShellView, both apps)", horizontal: 16, vertical: 12),
        HostPadding(name: "Sudoku Board (BoardView+Layout.themedBanner)", horizontal: 0, vertical: 0),
        HostPadding(name: "Minesweeper Board (MinesweeperBoardView.bannerSlot)", horizontal: 0, vertical: 0),
    ]

    /// Renders `BannerSlotView` through a real `NSHostingView` (the same
    /// AppKit-hosted path this repo's other layout-measurement tests use —
    /// see `ScaledSpacingTests.swift`) and reads back its AutoLayout-derived
    /// intrinsic size. A generous, fixed proposed width keeps the measured
    /// height independent of wrapping.
    private func measuredSize(of view: some View) -> CGSize {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 320, height: 1_000)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    /// A gate that has already resolved CLOSED (`hasPurchasedRemoveAds:
    /// true`), warmed synchronously via `shouldShowBanner(now:)` before
    /// `BannerSlotView` is even constructed — so `shouldShow` starts `false`
    /// (not `nil`) and the collapsed state is measured directly, with no
    /// dependency on `.task` ever firing (a different contract, already
    /// covered by `BannerSlotColdLaunchTests`).
    private func closedGate() async -> AdGate {
        let gate = AdGate(store: FakeAdGateStateStore(
            initial: AdGateState(firstLaunchAt: .distantPast, hasPurchasedRemoveAds: true)
        ))
        _ = await gate.shouldShowBanner(now: Date())
        return gate
    }

    @Test(
        "a gate-denied BannerSlotView contributes zero height, for every production host's padding",
        arguments: productionHosts
    )
    func collapsedContributesZeroHeight(host: HostPadding) async {
        let gate = await closedGate()
        let view = BannerSlotView(
            adProvider: FakeAdProvider(),
            adGate: gate,
            horizontalPadding: host.horizontal,
            verticalPadding: host.vertical
        )
        let size = measuredSize(of: view)
        #expect(
            size.height == 0,
            "\(host.name): a gate-denied BannerSlotView must contribute zero height to its parent, got \(size.height)pt"
        )
    }

    /// Sanity check on the measurement mechanism itself (not a new
    /// contract): with the SAME 16/12 padding a visible Today/Practice/
    /// Settings banner actually uses, a gate-OPEN `BannerSlotView` must
    /// measure a NON-zero height. Without this, a `measuredSize` regression
    /// that always returns 0 would make every row above pass for the wrong
    /// reason.
    @Test("sanity: a gate-allowed BannerSlotView measures non-zero height with the same harness")
    func visibleMeasuresNonZeroHeight() async {
        let gate = AdGate(store: FakeAdGateStateStore(
            initial: AdGateState(firstLaunchAt: Date().addingTimeInterval(-30 * 86_400))
        ))
        _ = await gate.shouldShowBanner(now: Date())
        let view = BannerSlotView(
            adProvider: FakeAdProvider(),
            adGate: gate,
            horizontalPadding: 16,
            verticalPadding: 12
        )
        let size = measuredSize(of: view)
        #expect(size.height > 0, "measurement harness must report non-zero height for a visible banner, got \(size.height)pt")
    }
}

#endif
