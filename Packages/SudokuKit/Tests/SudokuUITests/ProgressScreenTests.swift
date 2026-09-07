// ProgressScreenTests — #1021 Phase D/E2. Snapshots the shared
// `GameAppKit.ProgressScreen` composed with Sudoku's `RootViewModel`, over
// hand-built `ProgressModel` fixtures (this screen is a dumb view over a
// value — no VM/persistence needed to pin its render states).
//
// States pinned (content suite → strict `.image`, mirrors the retired
// Statistics screen's own suite): loaded (bests + marked calendar), loading
// (redacted placeholder), history-unavailable (empty calendar + footnote),
// `.accessibility3` (nothing truncates).
//
// Store fixture (iPhone/iPad/Mac light): #1021 Phase E2 — the old
// Statistics screen is retired for real this phase, so the "01-home" ASC
// store-screenshot slot (`mise-tasks/store/screenshots`,
// `scripts/build-ascspec-screenshots.py`) is repointed to THIS fixture.
// Mirrors the retired suite's own store fixture posture exactly: every
// difficulty fully populated (no "—" placeholder — a store screenshot must
// not show an empty state) and, new for Progress, a healthy fully-marked
// month so the calendar half of the screen isn't empty either. Numbers are
// the SAME merge math `ProgressViewModel.bestModel` performs (min best,
// summed count/average) applied by hand to the retired fixture's daily +
// practice record pairs, so this fixture reads as "the same player" the old
// store screenshot depicted.

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

// MARK: - Store fixture (#1021 Phase E2 — repoints the retired Statistics
// screen's store slot)

/// Merge math applied by hand to the retired suite's `storeRecords` daily +
/// practice pairs (best = min, count/average = summed) — see the file
/// header for why this reads as "the same player" the old fixture did:
///   easy:   daily(113,6816,48) + practice(97,2596,22)  → best 97,  count 70, avg 134
///   medium: daily(221,8246,31) + practice(163,2970,15) → best 163, count 46, avg 243
///   hard:   daily(383,6286,14) + practice(332,3096,8)  → best 332, count 22, avg 426
private let storeBests: [PersonalBestModel] = [
    best(difficulty: .easy, bestTimeText: "1:37", footnote: "70 solved · avg 2:14"),
    best(difficulty: .medium, bestTimeText: "2:43", footnote: "46 solved · avg 4:03"),
    best(difficulty: .hard, bestTimeText: "5:32", footnote: "22 solved · avg 7:06")
]

/// Every day of August 2025 completed — a store screenshot must not show an
/// empty calendar either.
private let storeHistory = StreakHistory(
    completedDays: Set((1...30).map { DayKey(year: 2025, month: 8, day: $0) }),
    today: DayKey(year: 2025, month: 8, day: 30)
)

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

    // MARK: - Store screenshot fixture (#1021 Phase E2, repoints #1040's
    // retired Statistics screen store slot)

    private func storeModel() -> ProgressModel {
        ProgressModel(
            bests: storeBests, history: storeHistory, month: loadedMonth,
            monthTitle: loadedMonthTitle, isLoading: false
        )
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotStoreIPhoneLight() {
        let host = hostingView(
            ProgressScreen(model: storeModel(), rootViewModel: makeRootViewModel()),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "ProgressScreen-iPhone-light-store")
        }
        assertViewStructure(of: host, named: "ProgressScreen-iPhone-light-store", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotStoreIPadLight() {
        let host = hostingView(
            ProgressScreen(model: storeModel(), rootViewModel: makeRootViewModel()),
            size: SnapshotLayouts.iPad,
            colorScheme: .light,
            sizeClass: .regular
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "ProgressScreen-iPad-light-store")
        }
        assertViewStructure(of: host, named: "ProgressScreen-iPad-light-store", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotStoreMacLight() {
        let host = hostingView(
            ProgressScreen(model: storeModel(), rootViewModel: makeRootViewModel()),
            size: SnapshotLayouts.mac,
            colorScheme: .light,
            sizeClass: .regular
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "ProgressScreen-Mac-light-store")
        }
        assertViewStructure(of: host, named: "ProgressScreen-Mac-light-store", record: SnapshotMode.recordMode)
    }
}
#endif
