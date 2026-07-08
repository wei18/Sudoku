// MinesweeperBoardSnapshotTests — themed-board visual baselines (#278 Tier-1
// Phase 2b).
//
// Records the themed Beginner board, light + dark, iPhone. These PNGs are the
// Designer's visual-verification surface for the proposed MinesweeperTheme vs
// docs/minesweeper/minesweeper-app-flow.prototype.html.
//
// State note: `MinesweeperBoardView(difficulty:seed:)` renders an all-hidden
// idle board deterministically (the view's in-body `.task { refresh() }` pulls
// the actor's idle snapshot, which is also all-hidden). That covered board
// exercises the covered-cell token, the status-bar chrome, the Reveal/Flag mode
// toggle, and the accent — the bulk of the themed surface. A mid-reveal state
// is deferred: reliably rendering revealed/flagged cells needs driving the
// actor async before capture, which the in-view refresh would overwrite (see
// the phase impl-notes). Recorded states are the deterministic primary surface.

#if canImport(AppKit)
import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import MinesweeperUI

import MinesweeperEngine
import MonetizationCore
import MonetizationTesting
import MonetizationUI

@MainActor
@Suite("MinesweeperBoardView — themed snapshots")
struct MinesweeperBoardSnapshotTests {

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotBeginnerCovered_iPhone_light() {
        let view = MinesweeperBoardView(difficulty: .beginner, seed: 42)
        assertUISnapshot(
            of: hostingView(view, size: SnapshotLayouts.iPhone, colorScheme: .light),
            as: .tolerantImage,
            named: "Board-iPhone-light-beginner-covered",
            record: SnapshotMode.recordMode
        )
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotBeginnerCovered_iPhone_dark() {
        let view = MinesweeperBoardView(difficulty: .beginner, seed: 42)
        assertUISnapshot(
            of: hostingView(view, size: SnapshotLayouts.iPhone, colorScheme: .dark),
            as: .tolerantImage,
            named: "Board-iPhone-dark-beginner-covered",
            record: SnapshotMode.recordMode
        )
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotBeginnerCovered_iPad_light() {
        let view = MinesweeperBoardView(difficulty: .beginner, seed: 42)
        assertUISnapshot(
            of: hostingView(view, size: SnapshotLayouts.iPad, colorScheme: .light, sizeClass: .regular),
            as: .tolerantImage,
            named: "Board-iPad-light-beginner-covered",
            record: SnapshotMode.recordMode
        )
    }

    // MARK: - #723 — ads-enabled, ad NOT loaded, slot reserved
    //
    // Mirrors SudokuKit's BoardViewBannerTests #723 fixtures (mirror
    // principle / verify-changes-on-both-apps). The gate is resolved once
    // before the view is built so `AdGate.lastKnownShouldShowBanner == true`
    // seeds the shared `BannerSlotView` and the first layout reserves the
    // 50pt rect (spinner placeholder, no ad) — the board never reflows when
    // the banner content later arrives.
    //
    // #732: the live `ProgressView` shown while `.loading` is a genuinely
    // timing-dependent spin animation, so capturing it made these baselines
    // environment-sensitive (pixel drift across machines/worktrees even on an
    // unmodified commit). We inject a static placeholder via
    // `BannerSlotView`'s `\.bannerSlotLoadingPreview` environment override
    // (production default stays the real spinner) AND keep `.tolerantImage`
    // per the #586 board-suite convention (AA-heavy boards) as a second line
    // of defense.

    private func adsAllowedGate() -> AdGate {
        AdGate(store: FakeAdGateStateStore(
            initial: AdGateState(
                firstLaunchAt: Date(timeIntervalSince1970: 0),
                hasPurchasedRemoveAds: false
            )
        ))
    }

    /// Deterministic stand-in for the live `ProgressView` spinner (#732) —
    /// same static ring look, no animation-frame dependency.
    private var deterministicBannerLoadingPreview: AnyView {
        AnyView(
            Circle()
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .frame(width: 16, height: 16)
        )
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotAdsEnabledUnloadedSlot_iPhone_light() async {
        let gate = adsAllowedGate()
        _ = await gate.shouldShowBanner(now: Date()) // warm the #723 hint
        let view = MinesweeperBoardView(
            difficulty: .beginner, seed: 42, adProvider: FakeAdProvider(), adGate: gate
        )
        .environment(\.bannerSlotLoadingPreview, deterministicBannerLoadingPreview)
        assertUISnapshot(
            of: hostingView(view, size: SnapshotLayouts.iPhone, colorScheme: .light),
            as: .tolerantImage,
            named: "Board-iPhone-light-banner-reserved",
            record: SnapshotMode.recordMode
        )
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotAdsEnabledUnloadedSlot_iPhone_dark() async {
        let gate = adsAllowedGate()
        _ = await gate.shouldShowBanner(now: Date()) // warm the #723 hint
        let view = MinesweeperBoardView(
            difficulty: .beginner, seed: 42, adProvider: FakeAdProvider(), adGate: gate
        )
        .environment(\.bannerSlotLoadingPreview, deterministicBannerLoadingPreview)
        assertUISnapshot(
            of: hostingView(view, size: SnapshotLayouts.iPhone, colorScheme: .dark),
            as: .tolerantImage,
            named: "Board-iPhone-dark-banner-reserved",
            record: SnapshotMode.recordMode
        )
    }
}
#endif
