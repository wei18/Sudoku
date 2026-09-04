// PracticeTabRootsComponentSnapshotTests — #1021 Phase C snapshot-coverage
// note: `GameShellKit` carries no `SnapshotTesting` dependency by design, so
// visual snapshot coverage for its shared TabRoots components lives in each
// app's test suite instead (mirrors `CompletionScreenTests.swift`'s header
// rationale). One direct snapshot per shared component the Practice hub
// consumes, in addition to the composed-screen snapshots in
// `PracticeHubViewTests.swift`.

#if canImport(AppKit)
import Foundation
import SnapshotTesting
import SwiftUI
import Testing
import GameShellUI
@testable import SudokuUI

@MainActor
@Suite("Practice TabRoots components — snapshots")
struct PracticeTabRootsComponentSnapshotTests {

    private static let sampleModel = SudokuPracticeCardsMapper.card(for: .medium)

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func practiceDifficultyCardView_default() {
        let host = hostingView(
            PracticeDifficultyCardView(model: Self.sampleModel, isSelected: false, action: {})
                .frame(width: 150),
            size: CGSize(width: 150, height: 220),
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "PracticeDifficultyCardView_default")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func practiceDifficultyCardView_selected() {
        let host = hostingView(
            PracticeDifficultyCardView(model: Self.sampleModel, isSelected: true, action: {})
                .frame(width: 150),
            size: CGSize(width: 150, height: 220),
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "PracticeDifficultyCardView_selected")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func boardPreviewView_9x9() {
        let preview = SudokuPracticeCardsMapper.card(for: .hard).preview
        let host = hostingView(
            BoardPreviewView(preview: preview).frame(width: 96, height: 96),
            size: CGSize(width: 96, height: 96),
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "BoardPreviewView_9x9")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func boardPreviewView_skeleton() {
        let host = hostingView(
            BoardPreviewView.skeleton(columns: 9, rows: 9).frame(width: 96, height: 96),
            size: CGSize(width: 96, height: 96),
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "BoardPreviewView_skeleton")
        }
    }
}
#endif
