// MinesweeperProgressViewModelTests — #1021 Phase D (mirrors Sudoku's
// `ProgressViewModelTests`). Pins the record→row mapping (average computed
// as total/count, nil best-time and zero-count cases, PRACTICE mode backing
// the personal-bests hero), the month streak-history construction from a
// fake by-day dictionary, and the graceful-degrade contract on fetch
// failure (`history == nil`, a nil store degrades every row to empty, both
// funnel through `errorReporter`).
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
/// calls — practice-only (daily is intentionally left unseeded: this VM
/// never reads daily records).
private func makeSeededStore() async throws -> MinesweeperPersonalRecordStore {
    let store = MinesweeperPersonalRecordStore(
        gateway: FakePrivateCKGateway(),
        clock: { Date(timeIntervalSince1970: 0) }
    )
    try await store.recordCompletion(puzzleId: "p-b-1", modeRaw: "practice", difficulty: .beginner, elapsedSeconds: 200)
    try await store.recordCompletion(puzzleId: "p-b-2", modeRaw: "practice", difficulty: .beginner, elapsedSeconds: 300)
    try await store.recordCompletion(puzzleId: "p-i-1", modeRaw: "practice", difficulty: .intermediate, elapsedSeconds: 61)
    // practice-expert: none → "—" placeholder.
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

    @Test func bestModelComputesAverageFromTotalOverCount() {
        let best = MinesweeperProgressViewModel.bestModel(
            difficulty: .beginner,
            record: msRecord(mode: "practice", difficulty: .beginner, best: 100, total: 1000, count: 4)
        )
        #expect(best.bestTimeText == "1:40")
        #expect(best.footnote == "4 cleared · avg 4:10")
    }

    @Test func emptyBestOmitsAverageAndBestTime() {
        let best = MinesweeperProgressViewModel.emptyBest(difficulty: .expert)
        #expect(best.bestTimeText == nil)
        #expect(best.footnote == "0 cleared")
    }

    @Test func bootstrapPopulatesBestsFromPracticeModeOnly() async throws {
        let viewModel = MinesweeperProgressViewModel(
            store: try await makeSeededStore(),
            completionSource: ScriptedCompletionSource()
        )
        await viewModel.bootstrap()
        #expect(viewModel.model.isLoading == false)
        #expect(viewModel.model.bests.map(\.id) == [Difficulty.beginner.rawValue, Difficulty.intermediate.rawValue, Difficulty.expert.rawValue])
        #expect(viewModel.model.bests[0].bestTimeText == "3:20")
        #expect(viewModel.model.bests[0].footnote == "2 cleared · avg 4:10")
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

    @Test func bootstrapFiresStatsViewedExactlyOnce() async {
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
