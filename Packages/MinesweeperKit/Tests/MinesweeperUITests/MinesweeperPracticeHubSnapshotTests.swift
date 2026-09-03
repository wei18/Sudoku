// MinesweeperPracticeHubSnapshotTests — #1021 Phase C.
//
// `MinesweeperPracticeHubViewTests.swift`'s header previously deferred
// snapshot rendering "per X1-X4 precedent for MS UI" — that was a stub-era
// stand-in, not a technical limitation (MS has full `SnapshotTesting`
// infra, exercised by `MinesweeperBoardSnapshotTests` etc.). Phase C's
// density-preview card redesign (design.md §3.2) is the first Practice-hub
// visual change worth pinning, so this file adds composed-screen coverage
// mirroring Sudoku's `PracticeHubViewTests.swift` `-default`/
// `-selectedHard`/`-accessibility3` set, plus the shared TabRoots component
// snapshots (per the #1021 snapshot-coverage note) sized to MS's wide
// (columns > rows) Expert board — the shape Sudoku's own component
// snapshots don't cover.

#if canImport(AppKit)
import Foundation
import SnapshotTesting
import SwiftUI
import Testing
import GameShellUI
@testable import MinesweeperUI
import MinesweeperEngine

@MainActor
@Suite("MinesweeperPracticeHubView — snapshots (#1021 Phase C)")
struct MinesweeperPracticeHubSnapshotTests {

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotDefaultIPhoneLight() {
        let host = hostingView(
            MinesweeperPracticeHubView(path: .constant([])),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        assertUISnapshot(of: host, as: .image, named: "PracticeHub-iPhone-light-default", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotSelectedExpertIPhoneLight() {
        let host = hostingView(
            MinesweeperPracticeHubView(path: .constant([]), initialDifficulty: .expert),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        assertUISnapshot(of: host, as: .image, named: "PracticeHub-iPhone-light-selectedHard", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotAccessibility3IPhoneLight() {
        let host = hostingView(
            MinesweeperPracticeHubView(path: .constant([])),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact,
            dynamicTypeSize: .accessibility3
        )
        assertUISnapshot(of: host, as: .image, named: "PracticeHub-iPhone-light-accessibility3", record: SnapshotMode.recordMode)
    }

    /// AX3 Dynamic Type pin on an iPad-width REGULAR size class — #1021
    /// Phase G, mirrors Sudoku's `PracticeHubViewTests.
    /// snapshotAccessibility3IPadLight`. Reproduces the Leader's iPad Pro 11
    /// finding: the shell's fixed, screen-filling `VStack` under the large
    /// "Practice" title overlapped the "Difficulty" section label at AX3.
    /// `PracticeHubShellView` now wraps that content in a `ScrollView` so it
    /// flows below the title instead — confirms no overlap here.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotAccessibility3IPadLight() {
        let host = hostingView(
            MinesweeperPracticeHubView(path: .constant([])),
            size: SnapshotLayouts.iPad,
            colorScheme: .light,
            sizeClass: .regular,
            dynamicTypeSize: .accessibility3
        )
        assertUISnapshot(of: host, as: .image, named: "PracticeHub-iPad-light-accessibility3", record: SnapshotMode.recordMode)
    }

    // MARK: - Shared TabRoots component snapshots

    private static let expertModel = MinesweeperPracticeCardsMapper.card(for: .expert)

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func practiceDifficultyCardView_default() {
        let host = hostingView(
            PracticeDifficultyCardView(model: Self.expertModel, isSelected: false, action: {})
                .frame(width: 150),
            size: CGSize(width: 150, height: 220),
            colorScheme: .light,
            sizeClass: .compact
        )
        assertUISnapshot(of: host, as: .image, named: "PracticeDifficultyCardView_default", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func practiceDifficultyCardView_selected() {
        let host = hostingView(
            PracticeDifficultyCardView(model: Self.expertModel, isSelected: true, action: {})
                .frame(width: 150),
            size: CGSize(width: 150, height: 220),
            colorScheme: .light,
            sizeClass: .compact
        )
        assertUISnapshot(of: host, as: .image, named: "PracticeDifficultyCardView_selected", record: SnapshotMode.recordMode)
    }

    /// Sudoku's own component-snapshot coverage is 9×9 only; MS's Expert
    /// preset (16 rows × 30 columns) is the shape that actually exercises
    /// `BoardPreviewView`'s non-square aspect ratio.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func boardPreviewView_16x30() {
        let preview = Self.expertModel.preview
        let host = hostingView(
            BoardPreviewView(preview: preview).frame(width: 96, height: 51),
            size: CGSize(width: 96, height: 51),
            colorScheme: .light,
            sizeClass: .compact
        )
        assertUISnapshot(of: host, as: .image, named: "BoardPreviewView_16x30", record: SnapshotMode.recordMode)
    }
}
#endif
