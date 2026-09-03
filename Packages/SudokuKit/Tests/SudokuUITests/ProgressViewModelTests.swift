// ProgressViewModelTests — #1021 Phase D. Pins the record→row mapping
// (average computed as total/count, nil best-time and zero-count cases,
// PRACTICE mode backing the personal-bests hero — see `ProgressViewModel`'s
// header for why), the month streak-history construction from a fake
// by-day dictionary, and the graceful-degrade contract on fetch failure
// (`history == nil`, one difficulty's row degrades to empty, both funnel
// through `errorReporter`).

import Foundation
import GameShellUI
import Persistence
import SnapshotTesting
import SudokuEngine
import SudokuGameState
import SwiftUI
import Telemetry
import Testing
@testable import SudokuUI

// MARK: - Scripted fakes

private actor ScriptedProgressPersistence: PersistenceProtocol {
    private let records: [String: PersonalRecord]
    private let completedByDay: [String: Set<String>]
    private let recordFetchError: PersistenceError?
    private let historyFetchError: PersistenceError?

    init(
        records: [PersonalRecord] = [],
        completedByDay: [String: Set<String>] = [:],
        recordFetchError: PersistenceError? = nil,
        historyFetchError: PersistenceError? = nil
    ) {
        self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.recordName, $0) })
        self.completedByDay = completedByDay
        self.recordFetchError = recordFetchError
        self.historyFetchError = historyFetchError
    }

    func bootstrap() async throws {}
    func latestInProgress() async throws -> SavedGameSummary? { nil }
    func loadOrCreate(puzzleId: String, mode: Mode, difficulty: Difficulty) async throws -> GameSessionSnapshot {
        throw PersistenceError.zoneNotProvisioned
    }
    func save(_ snapshot: GameSessionSnapshot, puzzleId: String, mode: Mode, difficulty: Difficulty) async throws {}
    func markCompleted(_ summary: SavedGameSummary) async throws {}
    func deleteAbandoned(recordName: String) async throws {}
    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> { [] }
    func fetchCompletedDailyIdsByDay() async throws -> [String: Set<String>] {
        if let historyFetchError { throw historyFetchError }
        return completedByDay
    }
    func fetchPersonalRecord(mode: Mode, difficulty: Difficulty) async throws -> PersonalRecord {
        if let recordFetchError { throw recordFetchError }
        return records["\(mode.rawValue)-\(difficulty.rawValue)"]
            ?? .empty(mode: mode, difficulty: difficulty, at: Date(timeIntervalSince1970: 0))
    }
    func upsertPersonalRecord(_ record: PersonalRecord) async throws {}
}

private func record(
    mode: Mode, difficulty: Difficulty, best: Int?, total: Int, count: Int
) -> PersonalRecord {
    PersonalRecord(
        recordName: "\(mode.rawValue)-\(difficulty.rawValue)",
        mode: mode, difficulty: difficulty,
        bestTimeSeconds: best, totalTimeSeconds: total, completedCount: count,
        lastUpdatedAt: Date(timeIntervalSince1970: 0), completedPuzzleIds: []
    )
}

private let fixedCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    return calendar
}()

private let fixedToday = Date(timeIntervalSince1970: 1_756_512_000) // 2025-08-30T00:00:00Z-ish, fixed reference

// MARK: - Suite

@MainActor
@Suite("ProgressViewModel — record → row mapping, month history")
struct ProgressViewModelTests {

    @Test func bestModelComputesAverageFromTotalOverCount() {
        let best = ProgressViewModel.bestModel(
            difficulty: .easy,
            record: record(mode: .practice, difficulty: .easy, best: 100, total: 1000, count: 4)
        )
        #expect(best.bestTimeText == "1:40")
        #expect(best.footnote == "4 solved · avg 4:10")
    }

    @Test func emptyBestOmitsAverageAndBestTime() {
        let best = ProgressViewModel.emptyBest(difficulty: .hard)
        #expect(best.bestTimeText == nil)
        #expect(best.footnote == "0 solved")
    }

    @Test func bootstrapPopulatesBestsFromPracticeModeOnly() async {
        let viewModel = ProgressViewModel(
            persistence: ScriptedProgressPersistence(records: [
                record(mode: .daily, difficulty: .easy, best: 1, total: 1, count: 1),
                record(mode: .practice, difficulty: .easy, best: 200, total: 1250, count: 5),
                record(mode: .practice, difficulty: .medium, best: 61, total: 61, count: 1)
                // practice-hard omitted → empty record → "—" placeholder.
            ]),
            calendar: fixedCalendar,
            now: { fixedToday }
        )
        await viewModel.bootstrap()
        #expect(viewModel.model.isLoading == false)
        #expect(viewModel.model.bests.map(\.id) == [Difficulty.easy.rawValue, Difficulty.medium.rawValue, Difficulty.hard.rawValue])
        #expect(viewModel.model.bests[0].bestTimeText == "3:20")
        #expect(viewModel.model.bests[0].footnote == "5 solved · avg 4:10")
        #expect(viewModel.model.bests[2].bestTimeText == nil)
        #expect(viewModel.model.bests[2].footnote == "0 solved")
    }

    @Test func bootstrapBuildsHistoryFromByDayKeys() async {
        let viewModel = ProgressViewModel(
            persistence: ScriptedProgressPersistence(completedByDay: [
                "2025-08-29": ["p1"],
                "2025-08-30": ["p2"]
            ]),
            calendar: fixedCalendar,
            now: { fixedToday }
        )
        await viewModel.bootstrap()
        #expect(viewModel.model.history != nil)
        #expect(viewModel.model.history?.current == 2)
    }

    @Test func bootstrapDegradesBestsToEmptyOnFetchFailure() async {
        let reporter = FakeErrorReporter()
        let viewModel = ProgressViewModel(
            persistence: ScriptedProgressPersistence(recordFetchError: .zoneNotProvisioned),
            errorReporter: reporter,
            calendar: fixedCalendar,
            now: { fixedToday }
        )
        await viewModel.bootstrap()
        #expect(viewModel.model.bests == Difficulty.allCases.map(ProgressViewModel.emptyBest))
        // 3 difficulties, each failure funneled.
        #expect(await reporter.received.count == 3)
    }

    @Test func bootstrapDegradesHistoryToNilOnFetchFailure() async {
        let reporter = FakeErrorReporter()
        let viewModel = ProgressViewModel(
            persistence: ScriptedProgressPersistence(historyFetchError: .zoneNotProvisioned),
            errorReporter: reporter,
            calendar: fixedCalendar,
            now: { fixedToday }
        )
        await viewModel.bootstrap()
        #expect(viewModel.model.history == nil)
        #expect(viewModel.model.isLoading == false)
        #expect(await reporter.received.count == 1)
    }

    @Test func bootstrapFiresStatsViewedExactlyOnce() async {
        let sink = ProgressRecordingSink()
        let telemetry = Telemetry(sinks: [sink])
        let viewModel = ProgressViewModel(
            persistence: ScriptedProgressPersistence(),
            telemetry: telemetry,
            calendar: fixedCalendar,
            now: { fixedToday }
        )
        await viewModel.bootstrap()
        await viewModel.bootstrap() // re-entry no-ops (`.task` re-fire guard)
        #expect(await sink.received == [.statsViewed])
    }

    @Test func timeLabelFormatsMinutesSecondsWithoutPlaceholder() {
        #expect(ProgressViewModel.timeLabel(192) == "3:12")
        #expect(ProgressViewModel.timeLabel(59) == "0:59")
        #expect(ProgressViewModel.timeLabel(600) == "10:00")
    }
}

private actor ProgressRecordingSink: TelemetrySink {
    private(set) var received: [TelemetryEvent] = []
    func receive(_ event: TelemetryEvent) async { received.append(event) }
}
