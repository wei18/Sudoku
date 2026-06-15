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
}
#endif
