// DailyHubViewModelWeekStripTests — #774 week-strip fetch/degrade/refresh
// integration, driven through `DailyHubViewModel.bootstrap()`/`refresh()`
// against `FakePersistence`'s per-date scripting.

import Foundation
import Testing
@testable import SudokuUI

import Persistence
import SudokuPersistence
import SudokuEngine
import SudokuKitTesting

@MainActor
@Suite("DailyHubViewModel — week strip (#774)")
struct DailyHubViewModelWeekStripTests {

    nonisolated(unsafe) private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    private func makeViewModel(
        provider: FakePuzzleProvider,
        persistence: FakePersistence
    ) -> DailyHubViewModel {
        DailyHubViewModel(
            provider: provider,
            persistence: persistence,
            dateProvider: { Self.fixedDate }
        )
    }

    /// Before any successful fetch, the strip is `.unknown` — 7 skeleton dots,
    /// no streak caption (never a false "0").
    @Test func weekStripStartsUnknown() async {
        let viewModel = makeViewModel(provider: FakePuzzleProvider(), persistence: FakePersistence())
        #expect(viewModel.weekStrip == .unknown)
    }

    @Test func bootstrapPopulatesSevenDaysWithTodayLast() async {
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)))
        let persistence = FakePersistence()
        let viewModel = makeViewModel(provider: provider, persistence: persistence)

        await viewModel.bootstrap()

        #expect(viewModel.weekStrip.days.count == 7)
        #expect(viewModel.weekStrip.days.last?.isToday == true)
        #expect(viewModel.weekStrip.days.first?.offsetFromToday == 6)
        #expect(viewModel.weekStrip.days.last?.offsetFromToday == 0)
    }

    /// Rule 1 (owner adjudication 2026-07-15): a day counts as completed if
    /// ANY difficulty was completed — a non-empty `fetchCompletedDailyIds`
    /// result for a given date must light that day's dot regardless of which
    /// puzzleId it contains.
    @Test func anyCompletedPuzzleIdLightsThatDaysDot() async {
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)))
        let persistence = FakePersistence()
        let yesterday = Self.fixedDate.addingTimeInterval(-86_400)
        await persistence.setCompletedDailyIds(["2020-01-01-medium"], for: yesterday)
        let viewModel = makeViewModel(provider: provider, persistence: persistence)

        await viewModel.bootstrap()

        let yesterdaySlot = viewModel.weekStrip.days.first { $0.offsetFromToday == 1 }
        #expect(yesterdaySlot?.isCompleted == true)
    }

    /// Today-only completion → 1-day streak, captioned (not hidden).
    @Test func todayOnlyCompletionShowsOneDayStreak() async {
        let provider = FakePuzzleProvider()
        let trio = FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)
        await provider.setDailyTrioResult(.success(trio))
        let persistence = FakePersistence()
        await persistence.setCompletedDailyIds([trio[0].identity.puzzleId], for: Self.fixedDate)
        let viewModel = makeViewModel(provider: provider, persistence: persistence)

        await viewModel.bootstrap()

        #expect(viewModel.weekStrip.streak == 1)
    }

    /// A genuine 0-day streak (nothing completed anywhere in the window)
    /// must NOT caption "0" — same degrade contract as the offline case.
    @Test func zeroStreakHidesCaptionRatherThanShowingZero() async {
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)))
        let persistence = FakePersistence()
        let viewModel = makeViewModel(provider: provider, persistence: persistence)

        await viewModel.bootstrap()

        #expect(viewModel.weekStrip.days.count == 7)
        #expect(viewModel.weekStrip.streak == nil)
    }

    /// Any single day's fetch failing degrades the WHOLE window — never a
    /// partial strip that could misrepresent a day as "missed" when its
    /// fetch actually failed.
    @Test func anyFetchFailureDegradesWholeWindowToUnknown() async {
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)))
        let persistence = FakePersistence()
        await persistence.setFetchCompletedDailyIdsError(.iCloudNotSignedIn)
        let viewModel = makeViewModel(provider: provider, persistence: persistence)

        await viewModel.bootstrap()

        #expect(viewModel.weekStrip == .unknown)
        // Trio cards must still render (graceful-degrade, same M10 contract
        // as the pre-existing overlay fetch).
        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected .loaded, got \(viewModel.state)")
            return
        }
        #expect(cards.count == 3)
    }

    /// `refresh()` re-runs the window fetch and picks up a newly-completed
    /// today without a full hub remount (#761 contract, extended to the strip).
    @Test func refreshUpdatesWeekStripWhenTodayBecomesCompleted() async {
        let provider = FakePuzzleProvider()
        let trio = FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)
        await provider.setDailyTrioResult(.success(trio))
        let persistence = FakePersistence()
        let viewModel = makeViewModel(provider: provider, persistence: persistence)

        await viewModel.bootstrap()
        #expect(viewModel.weekStrip.days.last?.isCompleted == false)

        await persistence.setCompletedDailyIds([trio[0].identity.puzzleId], for: Self.fixedDate)
        await viewModel.refresh()

        #expect(viewModel.weekStrip.days.last?.isCompleted == true)
        #expect(viewModel.weekStrip.streak == 1)
    }
}
