// ProgressScreenTests — #1021 Phase D. Snapshots the shared
// `GameAppKit.ProgressScreen` composed with Sudoku's `RootViewModel`, over
// hand-built `ProgressModel` fixtures (this screen is a dumb view over a
// value — no VM/persistence needed to pin its render states).
//
// States pinned (content suite → strict `.image`, mirrors the retired
// `StatsViewTests`): loaded (bests + marked calendar), loading (redacted
// placeholder), history-unavailable (empty calendar + footnote),
// `.accessibility3` (nothing truncates).

#if canImport(AppKit)
import Foundation
import GameAppKit
import GameCenterClient
import GameCenterTesting
import GameShellUI
import Persistence
import SnapshotTesting
import SudokuGameState
import SwiftUI
import SudokuEngine
import SudokuKitTesting
import Testing
@testable import SudokuUI

@MainActor
private func makeRootViewModel() -> RootViewModel {
    RootViewModel(gameCenter: FakeGameCenterClient(), persistence: FakePersistence())
}

private func best(
    difficulty: Difficulty, bestTimeText: String?, footnote: String
) -> PersonalBestModel {
    PersonalBestModel(
        id: difficulty.rawValue,
        title: difficulty.rawValue.capitalized,
        pipLevel: difficulty == .easy ? 1 : (difficulty == .medium ? 2 : 3),
        bestTimeText: bestTimeText,
        footnote: footnote
    )
}

private let loadedBests: [PersonalBestModel] = [
    best(difficulty: .easy, bestTimeText: "3:12", footnote: "14 solved · avg 4:02"),
    best(difficulty: .medium, bestTimeText: "6:55", footnote: "3 solved · avg 8:15"),
    best(difficulty: .hard, bestTimeText: nil, footnote: "0 solved")
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
@Suite("ProgressScreen — snapshots")
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
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "ProgressScreen-iPhone-light-loaded")
        }
        assertViewStructure(of: host, named: "ProgressScreen-iPhone-light-loaded", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotLoadingIPhoneLight() {
        let model = ProgressModel(
            bests: Difficulty.allCases.map { best(difficulty: $0, bestTimeText: nil, footnote: "0 solved") },
            history: nil, month: loadedMonth, monthTitle: loadedMonthTitle, isLoading: true
        )
        let host = hostingView(
            ProgressScreen(model: model, rootViewModel: makeRootViewModel()),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "ProgressScreen-iPhone-light-loading")
        }
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
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "ProgressScreen-iPhone-light-history-unavailable")
        }
        assertViewStructure(of: host, named: "ProgressScreen-iPhone-light-history-unavailable", record: SnapshotMode.recordMode)
    }

    // Dispatch requirement: at `.accessibility3` nothing truncates — the
    // "Personal bests" hero time, footnote, and calendar summary all keep
    // their full text.
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
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "ProgressScreen-iPhone-light-accessibility3")
        }
        assertViewStructure(of: host, named: "ProgressScreen-iPhone-light-accessibility3", record: SnapshotMode.recordMode)
    }
}
#endif
