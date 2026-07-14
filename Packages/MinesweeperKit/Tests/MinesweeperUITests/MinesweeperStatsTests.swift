// MinesweeperStatsTests — Statistics screen VM mapping + snapshot baselines
// (#773). Mirror of SudokuKit's StatsViewTests (per-app screens by scope
// note; the tests mirror too).
//
// VM tests pin the record→tile mapping (average computed as total/count,
// nil best-time and zero-count cases), the nil-store and fetch-failure
// degrade paths, and the one-shot `.statsViewed` telemetry event. Records
// are seeded through the REAL `MinesweeperPersonalRecordStore` over the
// in-memory `FakePrivateCKGateway` (the store's established test seam).
//
// Snapshots (content suite → strict `.image`): iPhone light (seeded data,
// incl. zero-count tiles showing the "—" placeholders), `.accessibility3`
// (stat columns + grid stack vertically), iPad regular (3-column reflow),
// Mac (960pt clamp-and-center). Baselines recorded once and eyeballed.

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

// MARK: - Seeding helpers

private actor StatsRecordingSink: TelemetrySink {
    private(set) var received: [TelemetryEvent] = []
    func receive(_ event: TelemetryEvent) async { received.append(event) }
}

/// Store over the in-memory fake gateway, seeded via real
/// `recordCompletion` calls (distinct puzzleIds so dedup never collapses).
private func makeSeededStore() async throws -> MinesweeperPersonalRecordStore {
    let store = MinesweeperPersonalRecordStore(
        gateway: FakePrivateCKGateway(),
        clock: { Date(timeIntervalSince1970: 0) }
    )
    // daily-beginner: 2 wins → count 2, best 100, avg 150
    try await store.recordCompletion(puzzleId: "d-b-1", modeRaw: "daily", difficulty: .beginner, elapsedSeconds: 100)
    try await store.recordCompletion(puzzleId: "d-b-2", modeRaw: "daily", difficulty: .beginner, elapsedSeconds: 200)
    // daily-intermediate: 1 win → 6:55 / 6:55
    try await store.recordCompletion(puzzleId: "d-i-1", modeRaw: "daily", difficulty: .intermediate, elapsedSeconds: 415)
    // daily-expert: none → "—" placeholders
    // practice-beginner: 1 win → 1:01
    try await store.recordCompletion(puzzleId: "p-b-1", modeRaw: "practice", difficulty: .beginner, elapsedSeconds: 61)
    // practice-intermediate: none
    // practice-expert: 1 win → 11:40
    try await store.recordCompletion(puzzleId: "p-e-1", modeRaw: "practice", difficulty: .expert, elapsedSeconds: 700)
    return store
}

private func msRecord(
    difficulty: Difficulty, best: Int?, total: Int, count: Int
) -> MinesweeperPersonalRecord {
    MinesweeperPersonalRecord(
        recordName: "daily-\(difficulty.rawValue)",
        modeRaw: "daily", difficulty: difficulty,
        bestTimeSeconds: best, totalTimeSeconds: total, completedCount: count,
        lastUpdatedAt: Date(timeIntervalSince1970: 0), completedPuzzleIds: []
    )
}

// MARK: - VM tests

@MainActor
@Suite("MinesweeperStatsViewModel — record → tile mapping")
struct MinesweeperStatsViewModelTests {

    @Test func tileComputesAverageFromTotalOverCount() {
        let tile = MinesweeperStatsTile.from(record: msRecord(difficulty: .beginner, best: 100, total: 1000, count: 4))
        #expect(tile.completedCount == 4)
        #expect(tile.bestTimeSeconds == 100)
        #expect(tile.averageTimeSeconds == 250)
    }

    @Test func tileWithZeroCountHasNoAverageAndNoBest() {
        let tile = MinesweeperStatsTile.from(record: msRecord(difficulty: .expert, best: nil, total: 0, count: 0))
        #expect(tile.completedCount == 0)
        #expect(tile.bestTimeSeconds == nil)
        #expect(tile.averageTimeSeconds == nil)
    }

    @Test func tileKeepsNilBestTimeIndependentOfCount() {
        // Defensive: the wire format allows completions without a best.
        let tile = MinesweeperStatsTile.from(record: msRecord(difficulty: .intermediate, best: nil, total: 300, count: 2))
        #expect(tile.bestTimeSeconds == nil)
        #expect(tile.averageTimeSeconds == 150)
    }

    @Test func bootstrapPopulatesBothSectionsInDifficultyOrder() async throws {
        let viewModel = MinesweeperStatsViewModel(store: try await makeSeededStore())
        await viewModel.bootstrap()
        #expect(viewModel.dailyTiles.map(\.difficulty) == [.beginner, .intermediate, .expert])
        #expect(viewModel.dailyTiles[0] == MinesweeperStatsTile(
            difficulty: .beginner, completedCount: 2, bestTimeSeconds: 100, averageTimeSeconds: 150
        ))
        #expect(viewModel.dailyTiles[2] == MinesweeperStatsTile.empty(difficulty: .expert))
        #expect(viewModel.practiceTiles[2] == MinesweeperStatsTile(
            difficulty: .expert, completedCount: 1, bestTimeSeconds: 700, averageTimeSeconds: 700
        ))
    }

    @Test func nilStoreRendersEmptyTiles() async {
        let viewModel = MinesweeperStatsViewModel(store: nil)
        await viewModel.bootstrap()
        #expect(viewModel.dailyTiles == Difficulty.allCases.map(MinesweeperStatsTile.empty))
        #expect(viewModel.practiceTiles == Difficulty.allCases.map(MinesweeperStatsTile.empty))
    }

    @Test func bootstrapDegradesToEmptyTilesOnFetchFailure() async {
        let gateway = FakePrivateCKGateway()
        await gateway.setFetchError(PersistenceError.zoneNotProvisioned)
        let reporter = FakeErrorReporter()
        let viewModel = MinesweeperStatsViewModel(
            store: MinesweeperPersonalRecordStore(gateway: gateway),
            errorReporter: reporter
        )
        await viewModel.bootstrap()
        #expect(viewModel.dailyTiles == Difficulty.allCases.map(MinesweeperStatsTile.empty))
        #expect(viewModel.practiceTiles == Difficulty.allCases.map(MinesweeperStatsTile.empty))
        // 2 modes × 3 difficulties, each failure funneled.
        #expect(await reporter.received.count == 6)
    }

    @Test func bootstrapFiresStatsViewedExactlyOnce() async {
        let sink = StatsRecordingSink()
        let telemetry = Telemetry(sinks: [sink])
        let viewModel = MinesweeperStatsViewModel(store: nil, telemetry: telemetry)
        await viewModel.bootstrap()
        await viewModel.bootstrap() // re-entry no-ops (`.task` re-fire guard)
        #expect(await sink.received == [.statsViewed])
    }

    @Test func timeLabelFormatsMinutesSecondsWithPlaceholder() {
        #expect(MinesweeperStatsTileView.timeLabel(nil) == "—")
        #expect(MinesweeperStatsTileView.timeLabel(192) == "3:12")
        #expect(MinesweeperStatsTileView.timeLabel(59) == "0:59")
        #expect(MinesweeperStatsTileView.timeLabel(600) == "10:00")
    }
}

// MARK: - Snapshots

#if canImport(AppKit)
@MainActor
@Suite("MinesweeperStatsView — snapshots")
struct MinesweeperStatsSnapshotTests {

    /// Build the view with seeded data, bootstrapped BEFORE hosting so the
    /// snapshot renders the loaded state (the in-view `.task` does not fire
    /// reliably in a bare NSHostingView).
    private func statsView() async throws -> MinesweeperStatsView {
        let viewModel = MinesweeperStatsViewModel(store: try await makeSeededStore())
        await viewModel.bootstrap()
        return MinesweeperStatsView(viewModel: viewModel)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotIPhoneLight() async throws {
        let host = hostingView(
            try await statsView(),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        assertUISnapshot(of: host, as: .image, named: "Stats-iPhone-light", record: SnapshotMode.recordMode)
        assertViewStructure(of: host, named: "Stats-iPhone-light", record: SnapshotMode.recordMode)
    }

    // Dispatch requirement: at `.accessibility3` the tile grid stacks
    // vertically with no truncation (stat columns become rows). Same
    // headless-host caveat as the Sudoku suite: semantic fonts don't grow
    // under `swift test`, so this pins the LAYOUT switch, not glyph scale.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotAccessibility3IPhoneLight() async throws {
        let host = hostingView(
            try await statsView(),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact,
            dynamicTypeSize: .accessibility3
        )
        assertUISnapshot(
            of: host, as: .image, named: "Stats-iPhone-light-accessibility3", record: SnapshotMode.recordMode
        )
        assertViewStructure(of: host, named: "Stats-iPhone-light-accessibility3", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotIPadLight() async throws {
        let host = hostingView(
            try await statsView(),
            size: SnapshotLayouts.iPad,
            colorScheme: .light,
            sizeClass: .regular
        )
        assertUISnapshot(of: host, as: .image, named: "Stats-iPad-light", record: SnapshotMode.recordMode)
        assertViewStructure(of: host, named: "Stats-iPad-light", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotMacLight() async throws {
        let host = hostingView(
            try await statsView(),
            size: SnapshotLayouts.mac,
            colorScheme: .light,
            sizeClass: .regular
        )
        assertUISnapshot(of: host, as: .image, named: "Stats-mac-light", record: SnapshotMode.recordMode)
        assertViewStructure(of: host, named: "Stats-mac-light", record: SnapshotMode.recordMode)
    }
}
#endif
