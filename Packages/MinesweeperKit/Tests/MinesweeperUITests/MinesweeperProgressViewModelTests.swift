// MinesweeperProgressViewModelTests — #1021 Phase D/E2 (mirrors Sudoku's
// `ProgressViewModelTests`). Pins the record→row mapping (both DAILY and
// PRACTICE merged per difficulty: best = the smaller of the two modes'
// bests, completedCount/average = the two modes' counts/totals summed — a
// "personal best" must not silently drop daily records), the month
// streak-history construction from a fake by-day dictionary, and the
// graceful-degrade contract on fetch failure (`history == nil`, a nil store
// degrades every row to empty, every failure funnels through
// `errorReporter`).
//
// Bests: seeded through the REAL `MinesweeperPersonalRecordStore` over the
// in-memory `FakePrivateCKGateway` (`MinesweeperStatsTests`'s established
// seam). History: a lightweight in-file fake conforming directly to
// `MinesweeperDailyOverlayReading` — the protocol is exactly the two methods
// this VM needs, so standing up a real `MinesweeperSavedGameStore` +
// session/snapshot plumbing here would be pure ceremony.

import Foundation
import MinesweeperEngine
import MinesweeperPersistence
import Persistence
import PersistenceTesting
import SnapshotTesting
import SwiftUI
import Telemetry
import Testing
@testable import MinesweeperUI

// MARK: - Fakes

private actor ScriptedCompletionSource: MinesweeperDailyOverlayReading {
    private let completedByDay: [String: Set<String>]
    private let fetchError: PersistenceError?

    init(completedByDay: [String: Set<String>] = [:], fetchError: PersistenceError? = nil) {
        self.completedByDay = completedByDay
        self.fetchError = fetchError
    }

    func fetchFailedDailyIds(for date: Date) async throws -> Set<String> { [] }
    func fetchCompletedDailyIdsByDay() async throws -> [String: Set<String>] {
        if let fetchError { throw fetchError }
        return completedByDay
    }
    // Phase B (#1021) requirement; the Progress VM never reads it.
    func latestInProgress() async throws -> MinesweeperSavedGameSummary? { nil }
}

private func msRecord(
    mode: String, difficulty: Difficulty, best: Int?, total: Int, count: Int
) -> MinesweeperPersonalRecord {
    MinesweeperPersonalRecord(
        recordName: "\(mode)-\(difficulty.rawValue)",
        modeRaw: mode, difficulty: difficulty,
        bestTimeSeconds: best, totalTimeSeconds: total, completedCount: count,
        lastUpdatedAt: Date(timeIntervalSince1970: 0), completedPuzzleIds: []
    )
}

/// Store over the in-memory fake gateway, seeded via real `recordCompletion`
/// calls — BOTH modes, so the merge (daily ∪ practice per difficulty) has
/// real data on each side to combine.
private func makeSeededStore() async throws -> MinesweeperPersonalRecordStore {
    let store = MinesweeperPersonalRecordStore(
        gateway: FakePrivateCKGateway(),
        clock: { Date(timeIntervalSince1970: 0) }
    )
    // beginner: daily is faster (100) than practice (200/300) → best 100, count 1+2=3.
    try await store.recordCompletion(puzzleId: "d-b-1", modeRaw: "daily", difficulty: .beginner, elapsedSeconds: 100)
    try await store.recordCompletion(puzzleId: "p-b-1", modeRaw: "practice", difficulty: .beginner, elapsedSeconds: 200)
    try await store.recordCompletion(puzzleId: "p-b-2", modeRaw: "practice", difficulty: .beginner, elapsedSeconds: 300)
    // intermediate: practice-only (no daily record seeded) → practice numbers alone.
    try await store.recordCompletion(puzzleId: "p-i-1", modeRaw: "practice", difficulty: .intermediate, elapsedSeconds: 61)
    // expert: neither mode seeded → "—" placeholder.
    return store
}

private actor ProgressRecordingSink: TelemetrySink {
    private(set) var received: [TelemetryEvent] = []
    func receive(_ event: TelemetryEvent) async { received.append(event) }
}

/// UTC, not `.current` — pins the by-day-key test's day boundary regardless
/// of the machine's local timezone (mirrors Sudoku's `ProgressViewModelTests`
/// fixture).
private let fixedCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    return calendar
}()

// MARK: - Suite

@MainActor
@Suite("MinesweeperProgressViewModel — record → row mapping, month history")
struct MinesweeperProgressViewModelTests {

    @Test func bestModelSumsCountsAndAveragesAcrossBothModes() {
        let best = MinesweeperProgressViewModel.bestModel(
            difficulty: .beginner,
            daily: msRecord(mode: "daily", difficulty: .beginner, best: 300, total: 300, count: 1),
            practice: msRecord(mode: "practice", difficulty: .beginner, best: 700, total: 700, count: 1)
        )
        #expect(best.bestTimeText == "5:00") // min(300, 700) == 300
        #expect(best.footnote == "2 cleared · avg 8:20") // (300+700)/2 == 500
    }

    /// #1021 Phase E2 CR: a "personal best per difficulty" must not silently
    /// drop daily records — when DAILY'S best time is the smaller (faster)
    /// one, it must win over practice, not be shadowed by it.
    @Test func bestModelDailyBestWinsWhenFasterThanPractice() {
        let best = MinesweeperProgressViewModel.bestModel(
            difficulty: .intermediate,
            daily: msRecord(mode: "daily", difficulty: .intermediate, best: 60, total: 60, count: 1),
            practice: msRecord(mode: "practice", difficulty: .intermediate, best: 200, total: 200, count: 1)
        )
        #expect(best.bestTimeText == "1:00")
    }

    /// A difficulty with ONLY daily data (never cleared in practice) must
    /// still surface daily's numbers, not fall back to the empty placeholder.
    @Test func bestModelWithOnlyDailyDataSurfacesDailyNumbers() {
        let best = MinesweeperProgressViewModel.bestModel(
            difficulty: .expert,
            daily: msRecord(mode: "daily", difficulty: .expert, best: 900, total: 1800, count: 2),
            practice: .empty(modeRaw: "practice", difficulty: .expert, at: Date(timeIntervalSince1970: 0))
        )
        #expect(best.bestTimeText == "15:00")
        #expect(best.footnote == "2 cleared · avg 15:00")
    }

    @Test func emptyBestOmitsAverageAndBestTime() {
        let best = MinesweeperProgressViewModel.emptyBest(difficulty: .expert)
        #expect(best.bestTimeText == nil)
        #expect(best.footnote == "0 cleared")
    }

    @Test func bootstrapMergesBestTimePerDifficultyAcrossBothModes() async throws {
        let viewModel = MinesweeperProgressViewModel(
            store: try await makeSeededStore(),
            completionSource: ScriptedCompletionSource()
        )
        await viewModel.bootstrap()
        #expect(viewModel.model.isLoading == false)
        #expect(viewModel.model.bests.map(\.id) == [Difficulty.beginner.rawValue, Difficulty.intermediate.rawValue, Difficulty.expert.rawValue])
        #expect(viewModel.model.bests[0].bestTimeText == "1:40") // min(100, 200) == 100
        #expect(viewModel.model.bests[0].footnote == "3 cleared · avg 3:20") // (100+200+300)/3 == 200
        #expect(viewModel.model.bests[1].bestTimeText == "1:01")
        #expect(viewModel.model.bests[1].footnote == "1 cleared · avg 1:01")
        #expect(viewModel.model.bests[2].bestTimeText == nil)
        #expect(viewModel.model.bests[2].footnote == "0 cleared")
    }

    @Test func nilStoreRendersEmptyBests() async {
        let viewModel = MinesweeperProgressViewModel(
            store: nil,
            completionSource: ScriptedCompletionSource()
        )
        await viewModel.bootstrap()
        #expect(viewModel.model.bests == Difficulty.allCases.map(MinesweeperProgressViewModel.emptyBest))
    }

    @Test func bootstrapBuildsHistoryFromByDayKeys() async {
        let viewModel = MinesweeperProgressViewModel(
            store: nil,
            completionSource: ScriptedCompletionSource(completedByDay: [
                "2025-08-29": ["p1"],
                "2025-08-30": ["p2"]
            ]),
            calendar: fixedCalendar,
            now: { Date(timeIntervalSince1970: 1_756_512_000) } // 2025-08-30T00:00:00Z
        )
        await viewModel.bootstrap()
        #expect(viewModel.model.history != nil)
        #expect(viewModel.model.history?.current == 2)
    }

    @Test func bootstrapDegradesHistoryToNilOnFetchFailure() async {
        let reporter = FakeErrorReporter()
        let viewModel = MinesweeperProgressViewModel(
            store: nil,
            completionSource: ScriptedCompletionSource(fetchError: .zoneNotProvisioned),
            errorReporter: reporter
        )
        await viewModel.bootstrap()
        #expect(viewModel.model.history == nil)
        #expect(viewModel.model.isLoading == false)
        #expect(await reporter.received.count == 1)
    }

    @Test func bootstrapFiresScreenViewedTelemetryExactlyOnce() async {
        let sink = ProgressRecordingSink()
        let telemetry = Telemetry(sinks: [sink])
        let viewModel = MinesweeperProgressViewModel(
            store: nil,
            completionSource: ScriptedCompletionSource(),
            telemetry: telemetry
        )
        await viewModel.bootstrap()
        await viewModel.bootstrap() // re-entry no-ops (`.task` re-fire guard)
        #expect(await sink.received == [.statsViewed])
    }

    @Test func timeLabelFormatsMinutesSecondsWithoutPlaceholder() {
        #expect(MinesweeperProgressViewModel.timeLabel(192) == "3:12")
        #expect(MinesweeperProgressViewModel.timeLabel(59) == "0:59")
        #expect(MinesweeperProgressViewModel.timeLabel(600) == "10:00")
    }
}
