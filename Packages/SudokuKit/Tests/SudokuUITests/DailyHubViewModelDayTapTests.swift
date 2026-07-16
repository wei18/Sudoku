// DailyHubViewModelDayTapTests — #826 past-day dot tap → completion review.
//
// Owner adjudication 2026-07-16: a past day with EXACTLY ONE completed
// difficulty opens that completion directly; MORE THAN ONE presents a
// confirmationDialog picker of that day's completed difficulties; today's
// dot and missed days stay inert. Covers difficulty derivation from
// puzzleIds (`reviewChoices(from:)`), direct-vs-picker branching, the
// past-day `openCompleted` fetch, and the #385 re-tap latch shared with the
// completed-card path.

import Foundation
import Testing
@testable import SudokuUI

import SudokuGameState
import Persistence
import SudokuPersistence
import SudokuEngine
import SudokuKitTesting

@MainActor
@Suite("DailyHubViewModel — past-day dot tap (#826)")
struct DailyHubViewModelDayTapTests {

    nonisolated private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    private func makeViewModel(
        persistence: FakePersistence,
        box: RoutePathBox
    ) -> DailyHubViewModel {
        DailyHubViewModel(
            provider: FakePuzzleProvider(),
            persistence: persistence,
            dateProvider: { Self.fixedDate },
            path: box.binding
        )
    }

    private func completedSnapshot(elapsedSeconds: Int) -> GameSessionSnapshot {
        let puzzle = FakePuzzleProvider.defaultPuzzle(difficulty: .easy, seed: 1)
        return GameSessionSnapshot(
            puzzle: puzzle,
            currentBoard: puzzle.solution,
            status: .completed,
            elapsedSeconds: elapsedSeconds,
            undoMoves: [],
            redoMoves: [],
            notes: NotesGrid()
        )
    }

    /// A past-day strip dot (`offsetFromToday` > 0) with the given completed ids.
    private func pastDay(completedPuzzleIds: Set<String>) -> DailyStripDay {
        DailyStripDay(
            offsetFromToday: 2,
            date: Self.fixedDate.addingTimeInterval(-2 * 86_400),
            isCompleted: !completedPuzzleIds.isEmpty,
            completedPuzzleIds: completedPuzzleIds
        )
    }

    /// Drains the MainActor queue until `box.routes` reaches `count` —
    /// same bounded-yield poll as `DailyHubViewModelInteractionTests`.
    private func waitForRouteCount(_ box: RoutePathBox, atLeast count: Int) async {
        for _ in 0..<1_000 {
            if box.routes.count >= count { return }
            await Task.yield()
        }
    }

    // MARK: - Difficulty derivation from puzzleIds

    @Test func reviewChoicesParsesDifficultyFromDailyPuzzleIds() {
        let choices = DailyStripLogic.reviewChoices(
            from: ["2026-07-14-hard", "2026-07-14-easy", "2026-07-14-medium"]
        )
        // Sorted easy → medium → hard regardless of Set ordering.
        #expect(choices.map(\.difficulty) == [.easy, .medium, .hard])
        #expect(choices.map(\.puzzleId) == ["2026-07-14-easy", "2026-07-14-medium", "2026-07-14-hard"])
    }

    @Test func reviewChoicesDropsMalformedIds() {
        let choices = DailyStripLogic.reviewChoices(
            from: ["2026-07-14-easy", "garbage", "2026-07-14-ultra"]
        )
        #expect(choices.map(\.puzzleId) == ["2026-07-14-easy"])
    }

    /// CR round 2: `isReviewable` is derived in init from the SAME parse the
    /// tap path uses — a completed day whose ids are ALL malformed is not
    /// reviewable, so the "tappable but inert" state is unrepresentable.
    @Test func dayWithOnlyMalformedIdsIsCompletedButNotReviewable() {
        let day = pastDay(completedPuzzleIds: ["garbage", "2026-07-14-ultra"])
        #expect(day.isCompleted == true)
        #expect(day.isReviewable == false)
        let reviewable = pastDay(completedPuzzleIds: ["2026-07-14-easy"])
        #expect(reviewable.isReviewable == true)
    }

    // MARK: - Direct open vs picker branching

    @Test func singleCompletedDifficultyOpensCompletionDirectly() async {
        let persistence = FakePersistence()
        await persistence.setLoadOrCreateSnapshot(completedSnapshot(elapsedSeconds: 613))
        let box = RoutePathBox()
        let viewModel = makeViewModel(persistence: persistence, box: box)

        viewModel.dayTapped(pastDay(completedPuzzleIds: ["2026-07-14-medium"]))
        await waitForRouteCount(box, atLeast: 1)

        #expect(viewModel.reviewPickerChoices == nil)
        #expect(box.routes == [
            .completion(puzzleId: "2026-07-14-medium", elapsedSeconds: 613, mistakeCount: 0)
        ])
    }

    @Test func multipleCompletedDifficultiesPresentPickerWithoutRouting() async {
        let persistence = FakePersistence()
        let box = RoutePathBox()
        let viewModel = makeViewModel(persistence: persistence, box: box)

        viewModel.dayTapped(pastDay(completedPuzzleIds: ["2026-07-14-hard", "2026-07-14-easy"]))

        #expect(viewModel.reviewPickerChoices?.map(\.difficulty) == [.easy, .hard])
        #expect(box.routes.isEmpty)
    }

    @Test func pickerSelectionClearsPickerAndRoutesToCompletion() async {
        let persistence = FakePersistence()
        await persistence.setLoadOrCreateSnapshot(completedSnapshot(elapsedSeconds: 901))
        let box = RoutePathBox()
        let viewModel = makeViewModel(persistence: persistence, box: box)
        viewModel.dayTapped(pastDay(completedPuzzleIds: ["2026-07-14-hard", "2026-07-14-easy"]))
        guard let choices = viewModel.reviewPickerChoices, choices.count == 2 else {
            Issue.record("expected 2 picker choices, got \(String(describing: viewModel.reviewPickerChoices))")
            return
        }

        viewModel.reviewChoiceSelected(choices[1])
        await waitForRouteCount(box, atLeast: 1)

        #expect(viewModel.reviewPickerChoices == nil)
        #expect(box.routes == [
            .completion(puzzleId: "2026-07-14-hard", elapsedSeconds: 901, mistakeCount: 0)
        ])
    }

    @Test func dismissReviewPickerClearsChoicesWithoutRouting() {
        let box = RoutePathBox()
        let viewModel = makeViewModel(persistence: FakePersistence(), box: box)
        viewModel.dayTapped(pastDay(completedPuzzleIds: ["2026-07-14-hard", "2026-07-14-easy"]))
        #expect(viewModel.reviewPickerChoices != nil)

        viewModel.dismissReviewPicker()

        #expect(viewModel.reviewPickerChoices == nil)
        #expect(box.routes.isEmpty)
    }

    // MARK: - Inert dots (test-pinned: today / missed never react)

    @Test func todaysCompletedDotIsInert() {
        let box = RoutePathBox()
        let viewModel = makeViewModel(persistence: FakePersistence(), box: box)
        let today = DailyStripDay(
            offsetFromToday: 0,
            date: Self.fixedDate,
            isCompleted: true,
            completedPuzzleIds: ["2026-07-16-easy"]
        )

        viewModel.dayTapped(today)

        #expect(viewModel.reviewPickerChoices == nil)
        #expect(box.routes.isEmpty)
    }

    @Test func missedPastDayIsInert() {
        let box = RoutePathBox()
        let viewModel = makeViewModel(persistence: FakePersistence(), box: box)

        viewModel.dayTapped(pastDay(completedPuzzleIds: []))

        #expect(viewModel.reviewPickerChoices == nil)
        #expect(box.routes.isEmpty)
    }

    /// CR round 2: a past day completed under a format the parser can't read
    /// (legacy schema / future drift) must be a full no-op at the VM too —
    /// no route, no picker — matching its non-tappable rendering.
    @Test func pastDayWithOnlyMalformedIdsIsInert() {
        let box = RoutePathBox()
        let viewModel = makeViewModel(persistence: FakePersistence(), box: box)

        viewModel.dayTapped(pastDay(completedPuzzleIds: ["garbage", "2026-07-14-ultra"]))

        #expect(viewModel.reviewPickerChoices == nil)
        #expect(box.routes.isEmpty)
    }

    // MARK: - #385 re-tap latch (shared with the completed-card path)

    @Test func rapidDoubleDayTapRoutesExactlyOnce() async {
        let persistence = FakePersistence()
        await persistence.setLoadOrCreateSnapshot(completedSnapshot(elapsedSeconds: 613))
        let box = RoutePathBox()
        let viewModel = makeViewModel(persistence: persistence, box: box)
        let day = pastDay(completedPuzzleIds: ["2026-07-14-medium"])

        viewModel.dayTapped(day)
        viewModel.dayTapped(day)
        await waitForRouteCount(box, atLeast: 1)
        await Task.yield()
        await Task.yield()

        #expect(box.routes.count == 1)
    }

    @Test func latchResetsSoLaterDayTapRoutesAgain() async {
        let persistence = FakePersistence()
        await persistence.setLoadOrCreateSnapshot(completedSnapshot(elapsedSeconds: 613))
        let box = RoutePathBox()
        let viewModel = makeViewModel(persistence: persistence, box: box)
        let day = pastDay(completedPuzzleIds: ["2026-07-14-medium"])

        viewModel.dayTapped(day)
        await waitForRouteCount(box, atLeast: 1)
        viewModel.dayTapped(day)
        await waitForRouteCount(box, atLeast: 2)

        #expect(box.routes.count == 2)
    }

    /// The past-day fetch failure funnels + falls back to `.board` — the
    /// same never-stuck contract as the completed-card path (#379).
    ///
    /// #830: `openCompleted` (shared by this path and the completed-card
    /// path) now calls `persistence.loadIfExists`, not `loadOrCreate` — this
    /// is `loadIfExists` THROWING, never swallowed into a virgin snapshot.
    @Test func pastDayLoadFailureFallsBackToBoard() async {
        let persistence = FakePersistence()
        await persistence.setLoadOrCreateError(.zoneNotProvisioned)
        let box = RoutePathBox()
        let viewModel = makeViewModel(persistence: persistence, box: box)

        viewModel.dayTapped(pastDay(completedPuzzleIds: ["2026-07-14-medium"]))
        await waitForRouteCount(box, atLeast: 1)

        #expect(box.routes == [.board(puzzleId: "2026-07-14-medium")])
    }

    /// #830: a confirmed-absent record (no error, no scripted snapshot) also
    /// falls back to `.board` — mirrors `completedCardConfirmedAbsentFallsBackToBoardWithoutReporting`
    /// for the past-day dot entry point.
    @Test func pastDayConfirmedAbsentFallsBackToBoard() async {
        let persistence = FakePersistence()
        let box = RoutePathBox()
        let viewModel = makeViewModel(persistence: persistence, box: box)

        viewModel.dayTapped(pastDay(completedPuzzleIds: ["2026-07-14-medium"]))
        await waitForRouteCount(box, atLeast: 1)

        #expect(box.routes == [.board(puzzleId: "2026-07-14-medium")])
    }
}

// MARK: - #826: strip-dot interactivity gate (view-level, headless)

/// Mirrors `BoardCellAccessibilityTests` (#473): `DailyStripView.isTappable`
/// drives BOTH the Button wrapping and the `.isButton` a11y trait, so pinning
/// it pins "button trait only on completed past dots" without a render harness.
@MainActor
@Suite("DailyStripView — dot interactivity (#826)")
struct DailyStripViewInteractivityTests {

    private static let referenceDate = Date(timeIntervalSince1970: 1_715_000_000)

    private func day(offset: Int, isCompleted: Bool) -> DailyStripDay {
        DailyStripDay(
            offsetFromToday: offset,
            date: Self.referenceDate.addingTimeInterval(-Double(offset) * 86_400),
            isCompleted: isCompleted,
            completedPuzzleIds: isCompleted ? ["2026-07-14-easy"] : []
        )
    }

    @Test func onlyCompletedPastDotsAreTappable() {
        let view = DailyStripView(snapshot: .unknown)
        #expect(view.isTappable(day(offset: 2, isCompleted: true)) == true)
        #expect(view.isTappable(day(offset: 0, isCompleted: true)) == false, "today stays inert even when completed")
        #expect(view.isTappable(day(offset: 2, isCompleted: false)) == false, "missed past days stay inert")
        #expect(view.isTappable(day(offset: 0, isCompleted: false)) == false)
    }

    /// CR round 2: a past COMPLETED day whose ids are all malformed gets no
    /// button (and therefore no `.isButton` trait / hint — `isTappable` is
    /// the single gate for all three).
    @Test func completedPastDotWithOnlyMalformedIdsIsNotTappable() {
        let view = DailyStripView(snapshot: .unknown)
        let malformed = DailyStripDay(
            offsetFromToday: 2,
            date: Self.referenceDate.addingTimeInterval(-2 * 86_400),
            isCompleted: true,
            completedPuzzleIds: ["garbage", "2026-07-14-ultra"]
        )
        #expect(view.isTappable(malformed) == false)
    }
}
