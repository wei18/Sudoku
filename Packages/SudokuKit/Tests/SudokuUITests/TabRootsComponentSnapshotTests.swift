// TabRootsComponentSnapshotTests — direct snapshot coverage for the shared
// `GameShellKit.TabRoots/` components Phase B consumes (#1021 Phase B).
//
// Binding snapshot-coverage note (Phase B dispatch): GameShellKit itself
// carries no snapshot-testing dependency by design, so Phase A shipped these
// components with unit + a11y-description tests only. This phase adds ONE
// direct snapshot per shared component it actually renders, here in the
// Sudoku suite (Minesweeper renders the identical component code with only
// its own theme injected — no separate visual language to pin).

#if canImport(AppKit)
import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import SudokuUI

import GameShellUI

@MainActor
@Suite("TabRoots shared components — direct snapshots (#1021 Phase B)")
struct TabRootsComponentSnapshotTests {

    private static let ninePreview = BoardPreview(
        columns: 9,
        rows: 9,
        cells: (0..<81).map { index in
            switch index % 3 {
            case 0: .given
            case 1: .filled
            default: .empty
            }
        }
    )!

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func boardPreviewView_9x9() {
        let host = hostingView(
            BoardPreviewView(preview: Self.ninePreview).frame(width: 120, height: 120),
            size: CGSize(width: 120, height: 120),
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "BoardPreviewView_9x9")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func boardPreviewView_skeleton() {
        let host = hostingView(
            BoardPreviewView.skeleton(columns: 9, rows: 9).frame(width: 120, height: 120),
            size: CGSize(width: 120, height: 120),
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "BoardPreviewView_skeleton")
        }
    }

    private static func cardModel(isCompleted: Bool, isSkeleton: Bool = false) -> DailyCardModel {
        DailyCardModel(
            id: "fixture",
            title: "Easy",
            pipLevel: 1,
            statusText: isCompleted ? "Solved · 3:12" : "Not started · 30 givens",
            preview: isSkeleton ? nil : ninePreview,
            isSkeleton: isSkeleton,
            isCompleted: isCompleted,
            accessibilityIdentifier: isCompleted ? "sudoku.dailyHub.card.completed" : nil
        )
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func dailyCardContent_notStarted() {
        let host = hostingView(
            DailyCardContent(model: Self.cardModel(isCompleted: false)).frame(width: 380),
            size: CGSize(width: 380, height: 100),
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "DailyCardContent_notStarted")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func dailyCardContent_completed() {
        let host = hostingView(
            DailyCardContent(model: Self.cardModel(isCompleted: true)).frame(width: 380),
            size: CGSize(width: 380, height: 100),
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "DailyCardContent_completed")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func dailyCardContent_skeleton() {
        let host = hostingView(
            DailyCardContent(model: Self.cardModel(isCompleted: false, isSkeleton: true)).frame(width: 380),
            size: CGSize(width: 380, height: 100),
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "DailyCardContent_skeleton")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func streakHeaderView_loaded() {
        let model = StreakHeaderModel(current: 5, longest: 12, last7: [true, true, false, true, true, true, true], isSkeleton: false)
        let host = hostingView(
            StreakHeaderView(model: model).frame(width: 380),
            size: CGSize(width: 380, height: 60),
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "StreakHeaderView_loaded")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func streakHeaderView_skeleton() {
        let model = StreakHeaderModel(current: 0, longest: nil, last7: Array(repeating: false, count: 7), isSkeleton: true)
        let host = hostingView(
            StreakHeaderView(model: model).frame(width: 380),
            size: CGSize(width: 380, height: 60),
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "StreakHeaderView_skeleton")
        }
    }
}
#endif
