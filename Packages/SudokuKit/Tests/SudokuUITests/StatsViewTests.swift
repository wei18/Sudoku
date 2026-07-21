// StatsViewTests — Statistics screen VM mapping + snapshot baselines (#773).
//
// VM tests pin the record→tile mapping (average computed as total/count,
// nil best-time and zero-count cases), the graceful-degrade contract
// (fetch failures funnel through errorReporter and keep empty tiles), and
// the one-shot `.statsViewed` telemetry event.
//
// Snapshots (content suite → strict `.image`): iPhone light (seeded data,
// incl. a zero-count tile showing the "—" placeholders), `.accessibility3`
// (tile stat columns + grid stack vertically, nothing truncates), iPad
// regular (3-column reflow), Mac (960pt clamp-and-center). Baselines
// recorded once and eyeballed.

import Foundation
import Persistence
import SnapshotTesting
import SudokuEngine
import SudokuGameState
import SwiftUI
import Telemetry
import Testing
@testable import SudokuUI

// MARK: - Scripted fakes

/// Per-(mode, difficulty) scripted PersonalRecord source. The shared
/// `SudokuKitTesting.FakePersistence` returns ONE record for every key;
/// this screen needs six distinct ones.
private actor ScriptedStatsPersistence: PersistenceProtocol {
    private let records: [String: PersonalRecord]
    private let fetchError: PersistenceError?

    init(records: [PersonalRecord] = [], fetchError: PersistenceError? = nil) {
        self.records = Dictionary(uniqueKeysWithValues: records.map { ($0.recordName, $0) })
        self.fetchError = fetchError
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
    func fetchCompletedDailyIdsByDay() async throws -> [String: Set<String>] { [:] }
    func fetchPersonalRecord(mode: Mode, difficulty: Difficulty) async throws -> PersonalRecord {
        if let fetchError { throw fetchError }
        return records["\(mode.rawValue)-\(difficulty.rawValue)"]
            ?? .empty(mode: mode, difficulty: difficulty, at: Date(timeIntervalSince1970: 0))
    }
    func upsertPersonalRecord(_ record: PersonalRecord) async throws {}
}

private actor StatsRecordingSink: TelemetrySink {
    private(set) var received: [TelemetryEvent] = []
    func receive(_ event: TelemetryEvent) async { received.append(event) }
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

/// Snapshot fixture: distinct values per tile, including a zero-count
/// daily-hard tile ("—" placeholders) so the empty state is pinned too.
private let seededRecords: [PersonalRecord] = [
    record(mode: .daily, difficulty: .easy, best: 192, total: 3360, count: 14),
    record(mode: .daily, difficulty: .medium, best: 415, total: 1500, count: 3),
    // daily-hard omitted → empty record → "—" placeholders
    record(mode: .practice, difficulty: .easy, best: 200, total: 1250, count: 5),
    record(mode: .practice, difficulty: .medium, best: 61, total: 61, count: 1),
    record(mode: .practice, difficulty: .hard, best: 700, total: 700, count: 1)
]

// MARK: - VM tests

@MainActor
@Suite("StatsViewModel — record → tile mapping")
struct StatsViewModelTests {

    @Test func tileComputesAverageFromTotalOverCount() {
        let tile = StatsTile.from(record: record(mode: .daily, difficulty: .easy, best: 100, total: 1000, count: 4))
        #expect(tile.completedCount == 4)
        #expect(tile.bestTimeSeconds == 100)
        #expect(tile.averageTimeSeconds == 250)
    }

    @Test func tileWithZeroCountHasNoAverageAndNoBest() {
        let tile = StatsTile.from(record: record(mode: .daily, difficulty: .hard, best: nil, total: 0, count: 0))
        #expect(tile.completedCount == 0)
        #expect(tile.bestTimeSeconds == nil)
        #expect(tile.averageTimeSeconds == nil)
    }

    @Test func tileKeepsNilBestTimeIndependentOfCount() {
        // Defensive: a record with completions but no best (not producible
        // via recordingCompletion, but the wire format allows it) must not
        // crash the average computation.
        let tile = StatsTile.from(record: record(mode: .practice, difficulty: .medium, best: nil, total: 300, count: 2))
        #expect(tile.bestTimeSeconds == nil)
        #expect(tile.averageTimeSeconds == 150)
    }

    @Test func bootstrapPopulatesBothSectionsInDifficultyOrder() async {
        let viewModel = StatsViewModel(persistence: ScriptedStatsPersistence(records: seededRecords))
        await viewModel.bootstrap()
        #expect(viewModel.dailyTiles.map(\.difficulty) == [.easy, .medium, .hard])
        #expect(viewModel.dailyTiles[0] == StatsTile(
            difficulty: .easy, completedCount: 14, bestTimeSeconds: 192, averageTimeSeconds: 240
        ))
        #expect(viewModel.dailyTiles[2] == StatsTile.empty(difficulty: .hard))
        #expect(viewModel.practiceTiles[2] == StatsTile(
            difficulty: .hard, completedCount: 1, bestTimeSeconds: 700, averageTimeSeconds: 700
        ))
    }

    @Test func bootstrapDegradesToEmptyTilesOnFetchFailure() async {
        let reporter = FakeErrorReporter()
        let viewModel = StatsViewModel(
            persistence: ScriptedStatsPersistence(fetchError: .zoneNotProvisioned),
            errorReporter: reporter
        )
        await viewModel.bootstrap()
        #expect(viewModel.dailyTiles == Difficulty.allCases.map(StatsTile.empty))
        #expect(viewModel.practiceTiles == Difficulty.allCases.map(StatsTile.empty))
        // 2 modes × 3 difficulties, each failure funneled.
        #expect(await reporter.received.count == 6)
    }

    @Test func bootstrapFiresStatsViewedExactlyOnce() async {
        let sink = StatsRecordingSink()
        let telemetry = Telemetry(sinks: [sink])
        let viewModel = StatsViewModel(
            persistence: ScriptedStatsPersistence(),
            telemetry: telemetry
        )
        await viewModel.bootstrap()
        await viewModel.bootstrap() // re-entry no-ops (`.task` re-fire guard)
        #expect(await sink.received == [.statsViewed])
    }

    @Test func timeLabelFormatsMinutesSecondsWithPlaceholder() {
        #expect(StatsTileView.timeLabel(nil) == "—")
        #expect(StatsTileView.timeLabel(192) == "3:12")
        #expect(StatsTileView.timeLabel(59) == "0:59")
        #expect(StatsTileView.timeLabel(600) == "10:00")
    }
}

// MARK: - Snapshots

#if canImport(AppKit)
@MainActor
@Suite("StatsView — snapshots")
struct StatsViewTests {

    /// Build the view with seeded data, bootstrapped BEFORE hosting so the
    /// snapshot renders the loaded state (the in-view `.task` does not fire
    /// reliably in a bare NSHostingView).
    private func statsView() async -> StatsView {
        let viewModel = StatsViewModel(persistence: ScriptedStatsPersistence(records: seededRecords))
        await viewModel.bootstrap()
        return StatsView(viewModel: viewModel)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotIPhoneLight() async {
        let host = hostingView(
            await statsView(),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "StatsView-iPhone-light")
        }
        assertViewStructure(of: host, named: "StatsView-iPhone-light", record: SnapshotMode.recordMode)
    }

    // Dispatch requirement: at `.accessibility3` the tile grid stacks
    // vertically with no truncation (stat columns become rows). Same
    // headless-host caveat as HomeViewTests' AX5 snapshot: semantic fonts
    // don't grow under `swift test`, so this pins the LAYOUT switch
    // (vertical stat stacking), not glyph-scale truncation.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotAccessibility3IPhoneLight() async {
        let host = hostingView(
            await statsView(),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact,
            dynamicTypeSize: .accessibility3
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "StatsView-iPhone-light-accessibility3")
        }
        assertViewStructure(of: host, named: "StatsView-iPhone-light-accessibility3", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotIPadLight() async {
        let host = hostingView(
            await statsView(),
            size: SnapshotLayouts.iPad,
            colorScheme: .light,
            sizeClass: .regular
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "StatsView-iPad-light")
        }
        assertViewStructure(of: host, named: "StatsView-iPad-light", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotMacLight() async {
        let host = hostingView(
            await statsView(),
            size: SnapshotLayouts.mac,
            colorScheme: .light,
            sizeClass: .regular
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "StatsView-Mac-light")
        }
        assertViewStructure(of: host, named: "StatsView-Mac-light", record: SnapshotMode.recordMode)
    }
}
#endif
