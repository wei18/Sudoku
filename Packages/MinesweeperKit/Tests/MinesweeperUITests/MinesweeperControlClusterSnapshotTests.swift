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

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func cluster_dark() {
        let host = hostingView(
            cluster,
            size: CGSize(width: 393, height: 120),
            colorScheme: .dark,
            sizeClass: .compact
        )
        assertUISnapshot(of: host, as: .image, named: "Cluster-compact-dark", record: SnapshotMode.recordMode)
    }
}
#endif
