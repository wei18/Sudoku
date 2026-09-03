// ProgressScreenTests — #1021 Phase D. Snapshots the shared
// `GameAppKit.ProgressScreen` composed with Minesweeper's
// `MinesweeperRootViewModel`, over hand-built `ProgressModel` fixtures (this
// screen is a dumb view over a value — no VM/persistence needed to pin its
// render states). Mirrors Sudoku's `ProgressScreenTests`.
//
// States pinned (content suite → strict `.image`, mirrors the retired
// `MinesweeperStatsTests`): loaded (bests + marked calendar), loading
// (redacted placeholder), history-unavailable (empty calendar + footnote),
// `.accessibility3` (nothing truncates).

#if canImport(AppKit)
import Foundation
import GameAppKit
import GameCenterClient
import GameCenterTesting
import GameShellUI
import MinesweeperEngine
import Persistence
import PersistenceTesting
import SnapshotTesting
import SwiftUI
import Testing
@testable import MinesweeperUI

@MainActor
private func makeRootViewModel() -> MinesweeperRootViewModel {
    MinesweeperRootViewModel(gameCenter: FakeGameCenterClient(), persistence: FakePersistence())
}

private func best(
    difficulty: Difficulty, bestTimeText: String?, footnote: String
) -> PersonalBestModel {
    PersonalBestModel(
        id: difficulty.rawValue,
        title: difficulty.rawValue.capitalized,
        pipLevel: difficulty == .beginner ? 1 : (difficulty == .intermediate ? 2 : 3),
        bestTimeText: bestTimeText,
        footnote: footnote
    )
}

private let loadedBests: [PersonalBestModel] = [
    best(difficulty: .beginner, bestTimeText: "0:54", footnote: "24 cleared · avg 1:08"),
    best(difficulty: .intermediate, bestTimeText: "2:21", footnote: "16 cleared · avg 2:56"),
    best(difficulty: .expert, bestTimeText: nil, footnote: "0 cleared")
]

private let loadedHistory = StreakHistory(
    completedDays: [
        DayKey(year: 2025, month: 8, day: 28),
        DayKey(year: 2025, month: 8, day: 29),
        DayKey(year: 2025, month: 8, day: 30)
    ],
    today: DayKey(year: 2025, month: 8, day: 30)
)

private let loadedMonth = DayKey(year: 2025, month: 8, day: 30)
private let loadedMonthTitle = "August 2025"

@MainActor
@Suite("ProgressScreen — snapshots (Minesweeper)")
struct ProgressScreenTests {

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotLoadedIPhoneLight() {
        let model = ProgressModel(
            bests: loadedBests, history: loadedHistory, month: loadedMonth,
            monthTitle: loadedMonthTitle, isLoading: false
        )
        let host = hostingView(
            ProgressScreen(model: model, rootViewModel: makeRootViewModel()),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        assertUISnapshot(of: host, as: .image, named: "ProgressScreen-iPhone-light-loaded", record: SnapshotMode.recordMode)
        assertViewStructure(of: host, named: "ProgressScreen-iPhone-light-loaded", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotLoadingIPhoneLight() {
        let model = ProgressModel(
            bests: Difficulty.allCases.map { best(difficulty: $0, bestTimeText: nil, footnote: "0 cleared") },
            history: nil, month: loadedMonth, monthTitle: loadedMonthTitle, isLoading: true
        )
        let host = hostingView(
            ProgressScreen(model: model, rootViewModel: makeRootViewModel()),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        assertUISnapshot(of: host, as: .image, named: "ProgressScreen-iPhone-light-loading", record: SnapshotMode.recordMode)
        assertViewStructure(of: host, named: "ProgressScreen-iPhone-light-loading", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotHistoryUnavailableIPhoneLight() {
        let model = ProgressModel(
            bests: loadedBests, history: nil, month: loadedMonth,
            monthTitle: loadedMonthTitle, isLoading: false
        )
        let host = hostingView(
            ProgressScreen(model: model, rootViewModel: makeRootViewModel()),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        assertUISnapshot(
            of: host, as: .image, named: "ProgressScreen-iPhone-light-history-unavailable", record: SnapshotMode.recordMode
        )
        assertViewStructure(
            of: host, named: "ProgressScreen-iPhone-light-history-unavailable", record: SnapshotMode.recordMode
        )
    }

    // Dispatch requirement: at `.accessibility3` nothing truncates.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotAccessibility3IPhoneLight() {
        let model = ProgressModel(
            bests: loadedBests, history: loadedHistory, month: loadedMonth,
            monthTitle: loadedMonthTitle, isLoading: false
        )
        let host = hostingView(
            ProgressScreen(model: model, rootViewModel: makeRootViewModel()),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact,
            dynamicTypeSize: .accessibility3
        )
        assertUISnapshot(
            of: host, as: .image, named: "ProgressScreen-iPhone-light-accessibility3", record: SnapshotMode.recordMode
        )
        assertViewStructure(
            of: host, named: "ProgressScreen-iPhone-light-accessibility3", record: SnapshotMode.recordMode
        )
    }
}
#endif
