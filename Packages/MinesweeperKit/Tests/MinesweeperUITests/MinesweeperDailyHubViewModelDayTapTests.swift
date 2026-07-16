// MinesweeperDailyHubViewModelDayTapTests — #826 past-day dot tap →
// completion review. Mirrors Sudoku's `DailyHubViewModelDayTapTests`.
//
// Owner adjudication 2026-07-16: a past day with EXACTLY ONE completed
// difficulty opens that completion directly; MORE THAN ONE presents a
// confirmationDialog picker; today's dot and missed days stay inert.
// MS's `.completion` push is fully synchronous (no stored elapsed to fetch,
// #284 — mirrors `cardTapped`'s completed branch, which has never needed
// the #385 latch either), so unlike Sudoku there is no async-latch matrix
// here; the route assertions are immediate.

import Foundation
import SwiftUI
import Testing
import MinesweeperEngine
@testable import MinesweeperUI

@MainActor
@Suite("MinesweeperDailyHubViewModel — past-day dot tap (#826)")
struct MinesweeperDailyHubViewModelDayTapTests {

    nonisolated private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    /// A past-day strip dot (`offsetFromToday` > 0) with the given completed ids.
    private func pastDay(completedPuzzleIds: Set<String>) -> MinesweeperDailyStripDay {
        MinesweeperDailyStripDay(
            offsetFromToday: 2,
            date: Self.fixedDate.addingTimeInterval(-2 * 86_400),
            isCompleted: !completedPuzzleIds.isEmpty,
            completedPuzzleIds: completedPuzzleIds
        )
    }

    // MARK: - Difficulty derivation from puzzleIds

    @Test func reviewChoicesParsesDifficultyFromDailyPuzzleIds() {
        let choices = MinesweeperDailyStripLogic.reviewChoices(
            from: ["daily-2026-07-14-expert", "daily-2026-07-14-beginner", "daily-2026-07-14-intermediate"]
        )
        // Sorted beginner → intermediate → expert regardless of Set ordering.
        #expect(choices.map(\.difficulty) == [.beginner, .intermediate, .expert])
        #expect(choices.map(\.puzzleId) == [
            "daily-2026-07-14-beginner",
            "daily-2026-07-14-intermediate",
            "daily-2026-07-14-expert",
        ])
    }

    @Test func reviewChoicesDropsMalformedIds() {
        let choices = MinesweeperDailyStripLogic.reviewChoices(
            from: ["daily-2026-07-14-beginner", "garbage", "daily-2026-07-14-legendary"]
        )
        #expect(choices.map(\.puzzleId) == ["daily-2026-07-14-beginner"])
    }

    /// CR round 2: `isReviewable` is derived in init from the SAME parse the
    /// tap path uses — a completed day whose ids are ALL malformed is not
    /// reviewable, so the "tappable but inert" state is unrepresentable.
    /// Mirrors Sudoku's `dayWithOnlyMalformedIdsIsCompletedButNotReviewable`.
    @Test func dayWithOnlyMalformedIdsIsCompletedButNotReviewable() {
        let day = pastDay(completedPuzzleIds: ["garbage", "daily-2026-07-14-legendary"])
        #expect(day.isCompleted == true)
        #expect(day.isReviewable == false)
        let reviewable = pastDay(completedPuzzleIds: ["daily-2026-07-14-beginner"])
        #expect(reviewable.isReviewable == true)
    }

    // MARK: - Direct open vs picker branching

    @Test func singleCompletedDifficultyOpensCompletionDirectlyWithPastDay() {
        var path: [AppRoute] = []
        let binding = Binding<[AppRoute]>(get: { path }, set: { path = $0 })
        let viewModel = MinesweeperDailyHubViewModel(path: binding)

        viewModel.dayTapped(pastDay(completedPuzzleIds: ["daily-2026-07-14-intermediate"]))

        #expect(viewModel.reviewPickerChoices == nil)
        // The route carries THAT day's UTC day-string, not nil/today —
        // derived via `MinesweeperSavedGameStore.dailyDay(fromRecordName:)`.
        #expect(path == [.completion(difficulty: .intermediate, mode: .daily, day: "2026-07-14")])
    }

    @Test func multipleCompletedDifficultiesPresentPickerWithoutRouting() {
        var path: [AppRoute] = []
        let binding = Binding<[AppRoute]>(get: { path }, set: { path = $0 })
        let viewModel = MinesweeperDailyHubViewModel(path: binding)

        viewModel.dayTapped(pastDay(completedPuzzleIds: ["daily-2026-07-14-expert", "daily-2026-07-14-beginner"]))

        #expect(viewModel.reviewPickerChoices?.map(\.difficulty) == [.beginner, .expert])
        #expect(path.isEmpty)
    }

    @Test func pickerSelectionClearsPickerAndRoutesToCompletion() {
        var path: [AppRoute] = []
        let binding = Binding<[AppRoute]>(get: { path }, set: { path = $0 })
        let viewModel = MinesweeperDailyHubViewModel(path: binding)
        viewModel.dayTapped(pastDay(completedPuzzleIds: ["daily-2026-07-14-expert", "daily-2026-07-14-beginner"]))
        guard let choices = viewModel.reviewPickerChoices, choices.count == 2 else {
            Issue.record("expected 2 picker choices, got \(String(describing: viewModel.reviewPickerChoices))")
            return
        }

        viewModel.reviewChoiceSelected(choices[1])

        #expect(viewModel.reviewPickerChoices == nil)
        #expect(path == [.completion(difficulty: .expert, mode: .daily, day: "2026-07-14")])
    }

    @Test func dismissReviewPickerClearsChoicesWithoutRouting() {
        var path: [AppRoute] = []
        let binding = Binding<[AppRoute]>(get: { path }, set: { path = $0 })
        let viewModel = MinesweeperDailyHubViewModel(path: binding)
        viewModel.dayTapped(pastDay(completedPuzzleIds: ["daily-2026-07-14-expert", "daily-2026-07-14-beginner"]))
        #expect(viewModel.reviewPickerChoices != nil)

        viewModel.dismissReviewPicker()

        #expect(viewModel.reviewPickerChoices == nil)
        #expect(path.isEmpty)
    }

    // MARK: - Inert dots (test-pinned: today / missed never react)

    @Test func todaysCompletedDotIsInert() {
        var path: [AppRoute] = []
        let binding = Binding<[AppRoute]>(get: { path }, set: { path = $0 })
        let viewModel = MinesweeperDailyHubViewModel(path: binding)
        let today = MinesweeperDailyStripDay(
            offsetFromToday: 0,
            date: Self.fixedDate,
            isCompleted: true,
            completedPuzzleIds: ["daily-2026-07-16-beginner"]
        )

        viewModel.dayTapped(today)

        #expect(viewModel.reviewPickerChoices == nil)
        #expect(path.isEmpty)
    }

    @Test func missedPastDayIsInert() {
        var path: [AppRoute] = []
        let binding = Binding<[AppRoute]>(get: { path }, set: { path = $0 })
        let viewModel = MinesweeperDailyHubViewModel(path: binding)

        viewModel.dayTapped(pastDay(completedPuzzleIds: []))

        #expect(viewModel.reviewPickerChoices == nil)
        #expect(path.isEmpty)
    }

    /// CR round 2: a past day completed under a format the parser can't read
    /// must be a full no-op at the VM too — no route, no picker — matching
    /// its non-tappable rendering. Mirrors Sudoku's
    /// `pastDayWithOnlyMalformedIdsIsInert`.
    @Test func pastDayWithOnlyMalformedIdsIsInert() {
        var path: [AppRoute] = []
        let binding = Binding<[AppRoute]>(get: { path }, set: { path = $0 })
        let viewModel = MinesweeperDailyHubViewModel(path: binding)

        viewModel.dayTapped(pastDay(completedPuzzleIds: ["garbage", "daily-2026-07-14-legendary"]))

        #expect(viewModel.reviewPickerChoices == nil)
        #expect(path.isEmpty)
    }
}

// MARK: - #826: strip-dot interactivity gate (view-level, headless)

/// Mirrors Sudoku's `DailyStripViewInteractivityTests`:
/// `MinesweeperDailyStripView.isTappable` drives BOTH the Button wrapping and
/// the `.isButton` a11y trait, so pinning it pins "button trait only on
/// completed past dots" without a render harness.
@MainActor
@Suite("MinesweeperDailyStripView — dot interactivity (#826)")
struct MinesweeperDailyStripViewInteractivityTests {

    private static let referenceDate = Date(timeIntervalSince1970: 1_715_000_000)

    private func day(offset: Int, isCompleted: Bool) -> MinesweeperDailyStripDay {
        MinesweeperDailyStripDay(
            offsetFromToday: offset,
            date: Self.referenceDate.addingTimeInterval(-Double(offset) * 86_400),
            isCompleted: isCompleted,
            completedPuzzleIds: isCompleted ? ["daily-2026-07-14-beginner"] : []
        )
    }

    @Test func onlyCompletedPastDotsAreTappable() {
        let view = MinesweeperDailyStripView(snapshot: .unknown)
        #expect(view.isTappable(day(offset: 2, isCompleted: true)) == true)
        #expect(view.isTappable(day(offset: 0, isCompleted: true)) == false, "today stays inert even when completed")
        #expect(view.isTappable(day(offset: 2, isCompleted: false)) == false, "missed past days stay inert")
        #expect(view.isTappable(day(offset: 0, isCompleted: false)) == false)
    }

    /// CR round 2: a past COMPLETED day whose ids are all malformed gets no
    /// button (and therefore no `.isButton` trait / hint — `isTappable` is
    /// the single gate for all three). Mirrors Sudoku's
    /// `completedPastDotWithOnlyMalformedIdsIsNotTappable`.
    @Test func completedPastDotWithOnlyMalformedIdsIsNotTappable() {
        let view = MinesweeperDailyStripView(snapshot: .unknown)
        let malformed = MinesweeperDailyStripDay(
            offsetFromToday: 2,
            date: Self.referenceDate.addingTimeInterval(-2 * 86_400),
            isCompleted: true,
            completedPuzzleIds: ["garbage", "daily-2026-07-14-legendary"]
        )
        #expect(view.isTappable(malformed) == false)
    }
}
