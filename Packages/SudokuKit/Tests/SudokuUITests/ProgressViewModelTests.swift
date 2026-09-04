// ProgressViewModelTests — #1021 Phase D/E2. Pins the record→row mapping
// (both DAILY and PRACTICE merged per difficulty — see `ProgressViewModel`'s
// header for why a "personal best" must not silently drop daily records:
// best = the smaller of the two modes' bests, completedCount/average = the
// two modes' counts/totals summed), the month streak-history construction
// from a fake by-day dictionary, and the graceful-degrade contract on fetch
// failure (`history == nil`, a failing (mode, difficulty) pair degrades to
// `.empty` before merging rather than wiping out the other mode's data,
// every failure funnels through `errorReporter`).

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
    private var records: [String: PersonalRecord]
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

    /// #1021 CR2 M1: lets `refreshReReadsBestsAfterBootstrap` mutate the
    /// fake store BETWEEN `bootstrap()` and `refresh()` — proving `refresh()`
    /// actually re-reads Persistence instead of replaying the bootstrap snapshot.
    func setRecords(_ newRecords: [PersonalRecord]) {
        records = Dictionary(uniqueKeysWithValues: newRecords.map { ($0.recordName, $0) })
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

    @Test func bestModelSumsCountsAndAveragesAcrossBothModes() {
        let best = ProgressViewModel.bestModel(
            difficulty: .easy,
            daily: record(mode: .daily, difficulty: .easy, best: 300, total: 300, count: 1),
            practice: record(mode: .practice, difficulty: .easy, best: 700, total: 700, count: 1)
        )
        #expect(best.bestTimeText == "5:00") // min(300, 700) == 300
        #expect(best.footnote == "2 solved · avg 8:20") // (300+700)/2 == 500
    }

    /// #1021 Phase E2 CR: a "personal best per difficulty" must not silently
    /// drop daily records — when DAILY'S best time is the smaller (faster)
    /// one, it must win over practice, not be shadowed by it.
    @Test func bestModelDailyBestWinsWhenFasterThanPractice() {
        let best = ProgressViewModel.bestModel(
            difficulty: .medium,
            daily: record(mode: .daily, difficulty: .medium, best: 60, total: 60, count: 1),
            practice: record(mode: .practice, difficulty: .medium, best: 200, total: 200, count: 1)
        )
        #expect(best.bestTimeText == "1:00")
    }

    /// A difficulty with ONLY daily data (never played in practice) must
    /// still surface daily's numbers, not fall back to the empty placeholder.
    @Test func bestModelWithOnlyDailyDataSurfacesDailyNumbers() {
        let best = ProgressViewModel.bestModel(
            difficulty: .hard,
            daily: record(mode: .daily, difficulty: .hard, best: 900, total: 1800, count: 2),
            practice: .empty(mode: .practice, difficulty: .hard, at: Date(timeIntervalSince1970: 0))
        )
        #expect(best.bestTimeText == "15:00")
        #expect(best.footnote == "2 solved · avg 15:00")
    }

    @Test func emptyBestOmitsAverageAndBestTime() {
        let best = ProgressViewModel.emptyBest(difficulty: .hard)
        #expect(best.bestTimeText == nil)
        #expect(best.footnote == "0 solved")
    }

    @Test func bootstrapMergesBestTimePerDifficultyAcrossBothModes() async {
        let viewModel = ProgressViewModel(
            persistence: ScriptedProgressPersistence(records: [
                // easy: daily is faster (100) than practice (200) → best 100, count 1+5=6.
                record(mode: .daily, difficulty: .easy, best: 100, total: 100, count: 1),
                record(mode: .practice, difficulty: .easy, best: 200, total: 1250, count: 5),
                // medium: practice-only (no daily record seeded) → practice numbers alone.
                record(mode: .practice, difficulty: .medium, best: 61, total: 61, count: 1)
                // hard: neither mode seeded → empty record on both → "—" placeholder.
            ]),
            calendar: fixedCalendar,
            now: { fixedToday }
        )
        await viewModel.bootstrap()
        #expect(viewModel.model.isLoading == false)
        #expect(viewModel.model.bests.map(\.id) == [Difficulty.easy.rawValue, Difficulty.medium.rawValue, Difficulty.hard.rawValue])
        #expect(viewModel.model.bests[0].bestTimeText == "1:40") // min(100, 200)
        #expect(viewModel.model.bests[0].footnote == "6 solved · avg 3:45") // (100+1250)/6 == 225
        #expect(viewModel.model.bests[1].bestTimeText == "1:01")
        #expect(viewModel.model.bests[1].footnote == "1 solved · avg 1:01")
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
        // 2 modes × 3 difficulties, each failure funneled independently.
        #expect(await reporter.received.count == 6)
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

    @Test func bootstrapFiresScreenViewedTelemetryExactlyOnce() async {
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

    /// #1021 CR2 M1: `refresh()` must actually re-read Persistence, not just
    /// replay `bootstrap()`'s snapshot — mutates the fake store's records
    /// AFTER bootstrap, then asserts `refresh()` picks up the new best.
    @Test func refreshReReadsBestsAfterBootstrap() async {
        let persistence = ScriptedProgressPersistence(records: [
            record(mode: .daily, difficulty: .easy, best: 100, total: 100, count: 1)
        ])
        let viewModel = ProgressViewModel(persistence: persistence, calendar: fixedCalendar, now: { fixedToday })
        await viewModel.bootstrap()
        #expect(viewModel.model.bests[0].bestTimeText == "1:40")
        await persistence.setRecords([
            record(mode: .daily, difficulty: .easy, best: 50, total: 100, count: 2)
        ])
        await viewModel.refresh()
        #expect(viewModel.model.bests[0].bestTimeText == "0:50")
        #expect(viewModel.model.bests[0].footnote == "2 solved · avg 0:50")
    }

    /// `refresh()` called before `bootstrap()` has ever landed must no-op
    /// (mirrors `DailyHubViewModel.refresh()`'s `hasBootstrapped` guard) —
    /// nothing to re-read yet, and it must not race the first bootstrap.
    @Test func refreshNoOpsBeforeBootstrap() async {
        let viewModel = ProgressViewModel(persistence: ScriptedProgressPersistence())
        await viewModel.refresh()
        #expect(viewModel.model.isLoading == true)
    }

    /// #1021 CR2 M1: `refresh()` must NOT re-fire `screenViewed` — that
    /// telemetry event is pinned to `bootstrap()` only (once per screen
    /// lifetime), even though the underlying data now refreshes repeatedly.
    @Test func refreshDoesNotRefireScreenViewedTelemetry() async {
        let sink = ProgressRecordingSink()
        let telemetry = Telemetry(sinks: [sink])
        let viewModel = ProgressViewModel(
            persistence: ScriptedProgressPersistence(),
            telemetry: telemetry,
            calendar: fixedCalendar,
            now: { fixedToday }
        )
        await viewModel.bootstrap()
        await viewModel.refresh()
        await viewModel.refresh()
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
