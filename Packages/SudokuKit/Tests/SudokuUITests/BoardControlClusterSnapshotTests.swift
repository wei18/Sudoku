// BoardControlClusterSnapshotTests — G4 on its own, STRICT (#1022 CR).
//
// Why this exists as a separate suite rather than tighter assertions inside the
// board snapshots: a control-sized change to the cluster is ~0.4-1% of a whole
// board frame, and the board suites use `.tolerantImage` (precision 0.95) for a
// good reason — the grid is antialiasing-heavy. So a glass restyle of the mode
// toggle drifted three Minesweeper baselines silently, inside the tolerance,
// and every gate stayed green (#1022 CR B1; the class is #1057).
//
// Splitting the cluster out gets strict comparison where it belongs — this is a
// content fixture, and `strict content / tolerant board` is already the repo's
// convention — without turning the AA-heavy board tests strict and flaky.
//
// Scope note: these render the DEFAULT cluster state deliberately. A tinted
// glass control blanks this entire capture path (see
// `SnapshotBlankBaselineGuardTests`), so the armed-digit and notes-on states
// cannot be pixel-tested here at all; they are simulator-verified. The guard
// suite will fail loudly if a future state change ever lands one of them here.

#if canImport(AppKit)
import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import SudokuUI

@MainActor
@Suite("G4 control cluster — strict, on its own (#1022)")
struct BoardControlClusterSnapshotTests {

    private func cluster(
        sizeClass: UserInterfaceSizeClass,
        pencilMode: Bool = false,
        canUndo: Bool = true
    ) -> some View {
        DigitPadView(
            pencilMode: pencilMode,
            canUndo: canUndo,
            canRedo: canUndo,
            sizeClass: sizeClass,
            remainingCounts: Array(repeating: 4, count: 9),
            armedDigit: nil,
            hasSelection: false,
            onDigit: { _ in },
            onErase: {},
            onTogglePencil: {},
            onUndo: {},
            onRedo: {}
        )
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func clusterRail_light() throws {
        let host = hostingView(
            cluster(sizeClass: .regular),
            size: CGSize(width: 300, height: 460),
            colorScheme: .light,
            sizeClass: .regular
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "Cluster-rail-light")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func clusterRail_dark() throws {
        let host = hostingView(
            cluster(sizeClass: .regular),
            size: CGSize(width: 300, height: 460),
            colorScheme: .dark,
            sizeClass: .regular
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "Cluster-rail-dark")
        }
    }

    // MARK: - Compact — the actual bottom cluster

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func clusterCompact_light() throws {
        let host = hostingView(
            cluster(sizeClass: .compact),
            size: CGSize(width: 393, height: 320),
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "Cluster-compact-light")
        }
    }

    /// Undo / Redo disabled — pins the #855 F-5 gray-out, which an
    /// unconditional `.foregroundStyle` once made indistinguishable from the
    /// always-enabled Erase.
    ///
    /// COMPACT, deliberately: the conditional ink that fix installed lives only
    /// in the compact row. The Mac rail leaves disabled styling to the system,
    /// and the regular-class fixtures render byte-identical enabled vs disabled
    /// through this capture path — so a `clusterRail_historyDisabled` case
    /// would assert nothing. Whether the rail dims correctly on a real Mac is
    /// not something this renderer can answer; #1039 owns macOS interaction.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func clusterCompact_historyDisabled_light() throws {
        let host = hostingView(
            cluster(sizeClass: .compact, canUndo: false),
            size: CGSize(width: 393, height: 320),
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "Cluster-compact-light-historyDisabled")
        }
    }
}
#endif
