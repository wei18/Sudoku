// ProgressScreenTests — #1021 Phase D/E2. Snapshots the shared
// `GameAppKit.ProgressScreen` composed with Minesweeper's
// `MinesweeperRootViewModel`, over hand-built `ProgressModel` fixtures (this
// screen is a dumb view over a value — no VM/persistence needed to pin its
// render states). Mirrors Sudoku's `ProgressScreenTests`.
//
// States pinned (content suite → strict `.image`, mirrors the retired
// Statistics screen's own suite): loaded (bests + marked calendar), loading
// (redacted placeholder), history-unavailable (empty calendar + footnote),
// `.accessibility3` (nothing truncates).
//
// Store fixture (iPhone/iPad/Mac light) + a Mac non-store "loaded" variant:
// #1021 Phase E2 — the old Statistics screen is retired for real this
// phase, so BOTH ASC slots that named the retired suite are repointed to
// fixtures here:
//   - "01-home" (all 3 devices) → `snapshotStore*` below, mirrors the
//     retired suite's own store-fixture setup exactly (same merge math
//     `MinesweeperProgressViewModel.bestModel` performs, applied by hand to
//     its daily+practice record pairs).
//   - "06-stats" (Mac-only, no iOS counterpart) → `snapshotLoadedMacLight`
//     below, the Mac-sized render of the regular (non-store) `loadedBests`
//     fixture — mirrors the retired suite's own Mac-light snapshot, which
//     rendered the same non-store fixture shape at Mac size.

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

// MARK: - Store fixture (#1021 Phase E2 — repoints the retired Statistics
// screen's store slot)

/// Merge math applied by hand to the retired suite's `makeStoreSeededStore()`'s
/// daily + practice pairs (best = min, count/average = summed):
///   beginner:     daily(54,1632,24) + practice(49,744,12)   → best 49,  count 36, avg 66
///   intermediate: daily(141,2816,16) + practice(129,1134,7) → best 129, count 23, avg 171
///   expert:       daily(308,3321,9) + practice(281,1312,4)  → best 281, count 13, avg 356
private let storeBests: [PersonalBestModel] = [
    best(difficulty: .beginner, bestTimeText: "0:49", footnote: "36 cleared · avg 1:06"),
    best(difficulty: .intermediate, bestTimeText: "2:09", footnote: "23 cleared · avg 2:51"),
    best(difficulty: .expert, bestTimeText: "4:41", footnote: "13 cleared · avg 5:56")
]

/// Every day of August 2025 completed — a store screenshot must not show an
/// empty calendar either.
private let storeHistory = StreakHistory(
    completedDays: Set((1...30).map { DayKey(year: 2025, month: 8, day: $0) }),
    today: DayKey(year: 2025, month: 8, day: 30)
)

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

    // MARK: - Mac non-store "loaded" fixture (#1021 Phase E2, repoints the
    // Mac-only "06-stats" ASC slot — no iOS counterpart)

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotLoadedMacLight() {
        let model = ProgressModel(
            bests: loadedBests, history: loadedHistory, month: loadedMonth,
            monthTitle: loadedMonthTitle, isLoading: false
        )
        let host = hostingView(
            ProgressScreen(model: model, rootViewModel: makeRootViewModel()),
            size: SnapshotLayouts.mac,
            colorScheme: .light,
            sizeClass: .regular
        )
        assertUISnapshot(of: host, as: .image, named: "ProgressScreen-Mac-light-loaded", record: SnapshotMode.recordMode)
        assertViewStructure(of: host, named: "ProgressScreen-Mac-light-loaded", record: SnapshotMode.recordMode)
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
        assertUISnapshot(of: host, as: .image, named: "ProgressScreen-iPhone-light-store", record: SnapshotMode.recordMode)
        assertViewStructure(of: host, named: "ProgressScreen-iPhone-light-store", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotStoreIPadLight() {
        let host = hostingView(
            ProgressScreen(model: storeModel(), rootViewModel: makeRootViewModel()),
            size: SnapshotLayouts.iPad,
            colorScheme: .light,
            sizeClass: .regular
        )
        assertUISnapshot(of: host, as: .image, named: "ProgressScreen-iPad-light-store", record: SnapshotMode.recordMode)
        assertViewStructure(of: host, named: "ProgressScreen-iPad-light-store", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotStoreMacLight() {
        let host = hostingView(
            ProgressScreen(model: storeModel(), rootViewModel: makeRootViewModel()),
            size: SnapshotLayouts.mac,
            colorScheme: .light,
            sizeClass: .regular
        )
        assertUISnapshot(of: host, as: .image, named: "ProgressScreen-Mac-light-store", record: SnapshotMode.recordMode)
        assertViewStructure(of: host, named: "ProgressScreen-Mac-light-store", record: SnapshotMode.recordMode)
    }
}
#endif
