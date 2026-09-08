// MinesweeperControlClusterSnapshotTests — G4 on its own, STRICT (#1022 CR).
//
// Mirror of SudokuKit's `BoardControlClusterSnapshotTests`, and the direct
// answer to the finding that motivated both: a glass restyle of THIS control
// drifted three MS board baselines by 0.41-1.07% and every gate stayed green,
// because the whole-board suites use `.tolerantImage` (precision 0.95) for the
// antialiasing-heavy grid. Rendering the cluster alone gets strict comparison
// on the part that must not drift silently, without making the board tests
// strict and flaky. Class tracked as #1057.
//
// Light only, and that is a measured decision rather than an oversight. A dark
// variant was recorded and compared: it differed from the light one by ZERO
// visible pixels (only alpha ≤7 antialiasing residue). The reason is that this
// capture path flips theme-token ink — `Color(light:dark:)` resolves through
// SwiftUI's `\.colorScheme` — but NOT system default label colours, which
// resolve from the AppKit drawing appearance `cacheDisplay` does not apply.
// This fixture's only ink is the system default: the view's single
// `foregroundStyle` sits in the FLAG branch, and flag mode tints its glass,
// and tinted glass blanks the entire capture. So no capturable state of this
// view can carry a dark-mode signal. The dark test was deleted rather than
// left advertising coverage it did not have; dark appearance is
// simulator-verified. (Sudoku's compact cluster DOES carry always-on theme ink
// and its dark variant differs in 5998 visible pixels — kept there.)
//
// Reveal mode only. Flag mode tints its glass, and tinted glass blanks this
// entire capture path (see `SnapshotBlankBaselineGuardTests`) — flag mode is
// simulator-verified instead. The guard suite fails loudly if that ever
// changes.

#if canImport(AppKit)
import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import MinesweeperUI

@MainActor
@Suite("G4 control cluster — strict, on its own (Minesweeper, #1022)")
struct MinesweeperControlClusterSnapshotTests {

    private var cluster: some View {
        MinesweeperControlClusterView(interactionMode: .reveal, onToggleMode: {})
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func cluster_light() {
        let host = hostingView(
            cluster,
            size: CGSize(width: 393, height: 120),
            colorScheme: .light,
            sizeClass: .compact
        )
        assertUISnapshot(of: host, as: .image, named: "Cluster-compact-light", record: SnapshotMode.recordMode)
    }
}
#endif
