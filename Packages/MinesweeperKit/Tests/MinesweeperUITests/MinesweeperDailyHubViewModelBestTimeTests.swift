// MinesweeperDailyHubViewModelBestTimeTests — #886 per-difficulty
// best-DAILY-time overlay. Mirrors SudokuKit's
// `DailyHubViewModelBestTimeTests`.
//
// Pins `MinesweeperDailyHubViewModel.fetchBestTimes`'s contract: rides the
// existing phase-2 `fillCompletionAndFailureOverlay` window, reads
// `personalRecordStore.fetch(modeRaw: "daily", difficulty:)` — the same seam
// `MinesweeperStatsViewModel.fetchTiles` already uses — and degrades PER
// DIFFICULTY independently (unlike the week-strip's all-or-nothing degrade):
// one difficulty's fetch failing must not blank out the other two. Uses the
// real `MinesweeperPersonalRecordStore` over an in-memory
// `FakePrivateCKGateway` (the store's established test seam — see
// `MinesweeperStatsTests.swift`), with the #886 per-recordName error
// injection added to the gateway for the degrade test.

import Foundation
import Testing
import MinesweeperEngine
import MinesweeperPersistence
import Persistence
import PersistenceTesting
import Telemetry
@testable import MinesweeperUI

@MainActor
@Suite("MinesweeperDailyHubViewModel — best-time overlay (#886)")
struct MinesweeperDailyHubViewModelBestTimeTests {

    nonisolated(unsafe) private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    private func makeViewModel(gateway: FakePrivateCKGateway) -> MinesweeperDailyHubViewModel {
        MinesweeperDailyHubViewModel(
            path: .constant([]),
            personalRecordStore: MinesweeperPersonalRecordStore(gateway: gateway, clock: { Self.fixedDate }),
            dateProvider: { Self.fixedDate }
        )
    }

    /// Happy path: every difficulty's `fetch` succeeds with a real best time
    /// (seeded via real `recordCompletion` calls — the store's own test
    /// seam) — all three cards carry it after bootstrap.
    @Test func bootstrapMergesBestTimePerDifficulty() async throws {
        let gateway = FakePrivateCKGateway()
        let store = MinesweeperPersonalRecordStore(gateway: gateway, clock: { Self.fixedDate })
        try await store.recordCompletion(puzzleId: "d-b-1", modeRaw: "daily", difficulty: .beginner, elapsedSeconds: 55)
        try await store.recordCompletion(puzzleId: "d-i-1", modeRaw: "daily", difficulty: .intermediate, elapsedSeconds: 240)
        try await store.recordCompletion(puzzleId: "d-e-1", modeRaw: "daily", difficulty: .expert, elapsedSeconds: 610)
        let viewModel = makeViewModel(gateway: gateway)

        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(cards.first { $0.difficulty == .beginner }?.bestTimeSeconds == 55)
        #expect(cards.first { $0.difficulty == .intermediate }?.bestTimeSeconds == 240)
        #expect(cards.first { $0.difficulty == .expert }?.bestTimeSeconds == 610)
    }

    /// Never-completed difficulty: no `recordCompletion` seeded — the store
    /// returns `MinesweeperPersonalRecord.empty(...)`, `bestTimeSeconds ==
    /// nil` — renders "—", same as a fetch failure (per the #886 spec's
    /// deliberate collapse).
    @Test func neverCompletedDifficultyRendersNilBestTime() async {
        let viewModel = makeViewModel(gateway: FakePrivateCKGateway())

        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(cards.allSatisfy { $0.bestTimeSeconds == nil })
    }

    /// No `personalRecordStore` injected at all (preview / legacy test
    /// callsites) — every card's `bestTimeSeconds` stays `nil`, never blocks.
    @Test func nilStoreRendersNilBestTimes() async {
        let viewModel = MinesweeperDailyHubViewModel(path: .constant([]), dateProvider: { Self.fixedDate })

        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(cards.allSatisfy { $0.bestTimeSeconds == nil })
    }

    /// #886's central contract: a fetch failure on ONE difficulty's
    /// `PersonalRecord` (scoped via the #886 per-recordName gateway error)
    /// must not blank the others — per-difficulty independent try/catch
    /// (`fetchBestTimes`), unlike `fetchWeekWindow`'s all-or-nothing degrade.
    @Test func perDifficultyFetchFailureDegradesOnlyThatDifficulty() async throws {
        let gateway = FakePrivateCKGateway()
        let store = MinesweeperPersonalRecordStore(gateway: gateway, clock: { Self.fixedDate })
        try await store.recordCompletion(puzzleId: "d-b-1", modeRaw: "daily", difficulty: .beginner, elapsedSeconds: 40)
        try await store.recordCompletion(puzzleId: "d-e-1", modeRaw: "daily", difficulty: .expert, elapsedSeconds: 500)
        // Intermediate's PersonalRecord fetch fails; beginner/expert's
        // `save`-established records are stored under their own recordNames
        // and unaffected.
        await gateway.setFetchError(PersistenceError.iCloudNotSignedIn, forRecordName: "daily-intermediate")
        let reporter = FakeErrorReporter()
        let viewModel = MinesweeperDailyHubViewModel(
            path: .constant([]),
            personalRecordStore: store,
            errorReporter: reporter,
            dateProvider: { Self.fixedDate }
        )

        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(cards.first { $0.difficulty == .beginner }?.bestTimeSeconds == 40)
        #expect(cards.first { $0.difficulty == .intermediate }?.bestTimeSeconds == nil)
        #expect(cards.first { $0.difficulty == .expert }?.bestTimeSeconds == 500)
        #expect(await reporter.received.count == 1)
    }

    /// A week-window degrade (no `savedGameStore` injected) must not
    /// suppress best times — they are an independent read with no
    /// false-claim risk (see `fillCompletionAndFailureOverlay`'s doc comment).
    @Test func weekWindowDegradeStillMergesBestTimes() async throws {
        let gateway = FakePrivateCKGateway()
        let store = MinesweeperPersonalRecordStore(gateway: gateway, clock: { Self.fixedDate })
        try await store.recordCompletion(puzzleId: "d-b-1", modeRaw: "daily", difficulty: .beginner, elapsedSeconds: 33)
        let viewModel = makeViewModel(gateway: gateway) // no savedGameStore → week window always nil

        await viewModel.bootstrap()

        #expect(viewModel.weekStrip == .unknown)
        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(cards.first { $0.difficulty == .beginner }?.bestTimeSeconds == 33)
        #expect(cards.allSatisfy { !$0.isCompleted && !$0.isFailed })
    }
}
