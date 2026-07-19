// DailyHubViewModelBestTimeTests — #886 per-difficulty best-DAILY-time overlay.
//
// Pins `DailyHubViewModel.fetchBestTimes`'s contract: rides the existing
// phase-2 `fillCompletionOverlay` window, reads
// `persistence.fetchPersonalRecord(mode: .daily, difficulty:)` — the same
// seam `StatsViewModel.fetchTiles` already uses — and degrades PER
// DIFFICULTY independently (unlike the week-strip's all-or-nothing degrade):
// one difficulty's fetch failing must not blank out the other two.

import Foundation
import Testing
@testable import SudokuUI

import Persistence
import SudokuPersistence
import SudokuEngine
import SudokuKitTesting
import Telemetry

@MainActor
@Suite("DailyHubViewModel — best-time overlay (#886)")
struct DailyHubViewModelBestTimeTests {

    nonisolated(unsafe) private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    private func record(difficulty: Difficulty, best: Int?) -> PersonalRecord {
        PersonalRecord(
            recordName: "daily-\(difficulty.rawValue)",
            mode: .daily,
            difficulty: difficulty,
            bestTimeSeconds: best,
            totalTimeSeconds: best ?? 0,
            completedCount: best == nil ? 0 : 1,
            lastUpdatedAt: Self.fixedDate,
            completedPuzzleIds: []
        )
    }

    private func makeViewModel(persistence: FakePersistence) -> DailyHubViewModel {
        let provider = FakePuzzleProvider()
        return DailyHubViewModel(
            provider: provider,
            persistence: persistence,
            dateProvider: { Self.fixedDate }
        )
    }

    /// Happy path: every difficulty's `fetchPersonalRecord` succeeds with a
    /// real best time — all three cards carry it after bootstrap.
    @Test func bootstrapMergesBestTimePerDifficulty() async {
        let persistence = FakePersistence()
        await persistence.setPersonalRecordResult(.success(record(difficulty: .easy, best: 61)), mode: .daily, difficulty: .easy)
        await persistence.setPersonalRecordResult(.success(record(difficulty: .medium, best: 221)), mode: .daily, difficulty: .medium)
        await persistence.setPersonalRecordResult(.success(record(difficulty: .hard, best: 303)), mode: .daily, difficulty: .hard)
        let viewModel = makeViewModel(persistence: persistence)

        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(cards.first { $0.difficulty == .easy }?.bestTimeSeconds == 61)
        #expect(cards.first { $0.difficulty == .medium }?.bestTimeSeconds == 221)
        #expect(cards.first { $0.difficulty == .hard }?.bestTimeSeconds == 303)
    }

    /// Never-completed difficulty: `fetchPersonalRecord` succeeds but
    /// `bestTimeSeconds` is `nil` on the record itself — renders "—", same as
    /// a fetch failure (per the #886 spec's deliberate collapse).
    @Test func neverCompletedDifficultyRendersNilBestTime() async {
        let persistence = FakePersistence()
        await persistence.setPersonalRecordResult(.success(record(difficulty: .easy, best: nil)), mode: .daily, difficulty: .easy)
        let viewModel = makeViewModel(persistence: persistence)

        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(cards.first { $0.difficulty == .easy }?.bestTimeSeconds == nil)
    }

    /// #886's central contract: a fetch failure on ONE difficulty must not
    /// blank the others — per-difficulty independent try/catch
    /// (`fetchBestTimes`), unlike `fetchWeekWindow`'s all-or-nothing degrade.
    @Test func perDifficultyFetchFailureDegradesOnlyThatDifficulty() async {
        let persistence = FakePersistence()
        await persistence.setPersonalRecordResult(.success(record(difficulty: .easy, best: 90)), mode: .daily, difficulty: .easy)
        await persistence.setPersonalRecordResult(.failure(.iCloudNotSignedIn), mode: .daily, difficulty: .medium)
        await persistence.setPersonalRecordResult(.success(record(difficulty: .hard, best: 250)), mode: .daily, difficulty: .hard)
        let reporter = FakeErrorReporter()
        let provider = FakePuzzleProvider()
        let viewModel = DailyHubViewModel(
            provider: provider,
            persistence: persistence,
            errorReporter: reporter,
            dateProvider: { Self.fixedDate }
        )

        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(cards.first { $0.difficulty == .easy }?.bestTimeSeconds == 90)
        #expect(cards.first { $0.difficulty == .medium }?.bestTimeSeconds == nil)
        #expect(cards.first { $0.difficulty == .hard }?.bestTimeSeconds == 250)
        #expect(await reporter.received.count == 1)
    }

    /// A week-window degrade (offline/signed-out) must not suppress best
    /// times — they are an independent read with no false-claim risk (see
    /// `fillCompletionOverlay`'s doc comment).
    @Test func weekWindowDegradeStillMergesBestTimes() async {
        let persistence = FakePersistence()
        await persistence.setFetchCompletedDailyIdsError(.iCloudNotSignedIn)
        await persistence.setPersonalRecordResult(.success(record(difficulty: .easy, best: 42)), mode: .daily, difficulty: .easy)
        let viewModel = makeViewModel(persistence: persistence)

        await viewModel.bootstrap()

        #expect(viewModel.weekStrip == .unknown)
        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(cards.first { $0.difficulty == .easy }?.bestTimeSeconds == 42)
        #expect(cards.allSatisfy { !$0.isCompleted })
    }

    /// `refresh()` re-runs the same overlay — a freshly-set best time must
    /// show up without a full hub remount (mirrors the completion-overlay
    /// refresh contract in `DailyHubViewModelRefreshTests`).
    @Test func refreshPicksUpNewlySetBestTime() async {
        let persistence = FakePersistence()
        let viewModel = makeViewModel(persistence: persistence)

        await viewModel.bootstrap()
        guard case .loaded(let initialCards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(initialCards.first { $0.difficulty == .easy }?.bestTimeSeconds == nil)

        await persistence.setPersonalRecordResult(.success(record(difficulty: .easy, best: 77)), mode: .daily, difficulty: .easy)
        await viewModel.refresh()

        guard case .loaded(let refreshedCards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(refreshedCards.first { $0.difficulty == .easy }?.bestTimeSeconds == 77)
    }
}
