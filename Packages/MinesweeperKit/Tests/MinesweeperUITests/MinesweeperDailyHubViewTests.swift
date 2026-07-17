// MinesweeperDailyHubViewTests — coverage for the #290 date-seeded Daily hub.
//
// Verifies the view + VM instantiate, the live provider yields a deterministic
// trio, completion ids mark cards, and a card tap pushes the daily `.board`
// route. Mirrors the shape of SudokuUI's DailyHubViewModel tests.

import Foundation
import SwiftUI
import Testing
@testable import MinesweeperUI
import MinesweeperEngine

@MainActor
@Suite struct MinesweeperDailyHubViewTests {

    @Test func instantiatesWithViewModel() {
        let view = MinesweeperDailyHubView(
            viewModel: MinesweeperDailyHubViewModel(path: .constant([]))
        )
        _ = view
    }

    @Test func liveProviderYieldsTrioInDifficultyOrder() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let trio = LiveMinesweeperDailyProvider().dailyTrio(date: date)
        #expect(trio.count == 3)
        #expect(trio.map(\.difficulty) == [.beginner, .intermediate, .expert])
        // Seeds match the engine's daily derivation.
        #expect(trio[0].seed == MinesweeperDaily.seed(date: date, difficulty: .beginner))
        #expect(trio[0].puzzleId == MinesweeperDaily.puzzleId(date: date, difficulty: .beginner))
    }

    @Test func bootstrapLoadsThreeCardsAllUncompletedWithoutPersistence() async {
        let viewModel = MinesweeperDailyHubViewModel(
            path: .constant([]),
            dateProvider: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        await viewModel.bootstrap()
        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected .loaded, got \(viewModel.state)")
            return
        }
        #expect(cards.count == 3)
        #expect(cards.allSatisfy { !$0.isCompleted })
    }

    @Test func mergeMarksCompletedCardsFromCompletedIds() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let trio = LiveMinesweeperDailyProvider().dailyTrio(date: date)
        let completedId = MinesweeperDaily.puzzleId(date: date, difficulty: .intermediate)
        let cards = MinesweeperDailyHubViewModel.mergeCards(trio: trio, completed: [completedId])
        let intermediate = cards.first { $0.difficulty == .intermediate }
        #expect(intermediate?.isCompleted == true)
        #expect(cards.filter(\.isCompleted).count == 1)
    }

    @Test func mergeWithEmptyCompletedMarksNothing() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let trio = LiveMinesweeperDailyProvider().dailyTrio(date: date)
        let cards = MinesweeperDailyHubViewModel.mergeCards(trio: trio, completed: [])
        #expect(cards.allSatisfy { !$0.isCompleted })
    }

    @Test func cardTapPushesDailyBoardRoute() async {
        var path: [AppRoute] = []
        let binding = Binding<[AppRoute]>(get: { path }, set: { path = $0 })
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let viewModel = MinesweeperDailyHubViewModel(path: binding, dateProvider: { date })
        await viewModel.bootstrap()
        guard case .loaded(let cards) = viewModel.state, let first = cards.first else {
            Issue.record("expected loaded cards")
            return
        }
        viewModel.cardTapped(first)
        // #329: tapping a Daily card pushes a daily-mode board so the win submits
        // to the recurring daily leaderboard.
        #expect(path == [.board(difficulty: first.difficulty, seed: first.seed, mode: .daily)])
    }

    // #386: re-tapping an already-SOLVED daily routes to `.completion` (re-see
    // the result + leaderboard), NOT a fresh `.board` (dead replay).
    @Test func solvedCardTapPushesCompletionRoute() async {
        var path: [AppRoute] = []
        let binding = Binding<[AppRoute]>(get: { path }, set: { path = $0 })
        let viewModel = MinesweeperDailyHubViewModel(path: binding)
        // #842: `cardTapped` no-ops while `isPhase2Pending` — bootstrap first
        // so the gate has cleared (no `savedGameStore` wired here, so phase-2
        // resolves with no CK traffic).
        await viewModel.bootstrap()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = LiveMinesweeperDailyProvider().dailyTrio(date: date)[0]
        let solved = MinesweeperDailyCard(entry: entry, isCompleted: true)
        viewModel.cardTapped(solved)
        #expect(path == [.completion(difficulty: solved.difficulty, mode: .daily)])
    }

    // #386: an un-solved daily card still pushes the daily-mode board (unchanged
    // pre-#386 behavior) so a first solve submits to the daily leaderboard.
    @Test func unsolvedCardTapPushesDailyBoardRoute() async {
        var path: [AppRoute] = []
        let binding = Binding<[AppRoute]>(get: { path }, set: { path = $0 })
        let viewModel = MinesweeperDailyHubViewModel(path: binding)
        await viewModel.bootstrap()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = LiveMinesweeperDailyProvider().dailyTrio(date: date)[0]
        let unsolved = MinesweeperDailyCard(entry: entry, isCompleted: false)
        viewModel.cardTapped(unsolved)
        #expect(path == [.board(difficulty: unsolved.difficulty, seed: unsolved.seed, mode: .daily)])
    }

    // MARK: - Epic 8: failed-card state and replay routing

    // mergeCards marks a card failed when its puzzleId is in the failed set
    // and NOT in the completed set (completed win takes priority).
    @Test func mergeMarkesFailedCard() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let trio = LiveMinesweeperDailyProvider().dailyTrio(date: date)
        let failedId = trio[0].puzzleId
        let cards = MinesweeperDailyHubViewModel.mergeCards(
            trio: trio,
            completed: [],
            failed: [failedId]
        )
        #expect(cards[0].isFailed == true)
        #expect(cards[1].isFailed == false)
        #expect(cards[2].isFailed == false)
    }

    // A completed (won) card takes priority over failed even if both sets
    // contain the same id (belt-and-suspenders: shouldn't happen in prod).
    @Test func completedTakesPriorityOverFailed() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let trio = LiveMinesweeperDailyProvider().dailyTrio(date: date)
        let bothId = trio[1].puzzleId
        let cards = MinesweeperDailyHubViewModel.mergeCards(
            trio: trio,
            completed: [bothId],
            failed: [bothId]
        )
        #expect(cards[1].isCompleted == true)
        #expect(cards[1].isFailed == false)
    }

    // A failed card tap pushes `.replayDailyBoard` (unscored, no persistence).
    @Test func failedCardTapPushesReplayRoute() async {
        var path: [AppRoute] = []
        let binding = Binding<[AppRoute]>(get: { path }, set: { path = $0 })
        let viewModel = MinesweeperDailyHubViewModel(path: binding)
        await viewModel.bootstrap()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = LiveMinesweeperDailyProvider().dailyTrio(date: date)[0]
        let failedCard = MinesweeperDailyCard(entry: entry, isCompleted: false, isFailed: true)
        viewModel.cardTapped(failedCard)
        #expect(path == [.replayDailyBoard(difficulty: entry.difficulty, seed: entry.seed)])
    }

    // A failed-card replay route is distinct from the scored daily route.
    @Test func replayRouteIsDistinctFromScoredDaily() async {
        var path: [AppRoute] = []
        let binding = Binding<[AppRoute]>(get: { path }, set: { path = $0 })
        let viewModel = MinesweeperDailyHubViewModel(path: binding)
        await viewModel.bootstrap()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = LiveMinesweeperDailyProvider().dailyTrio(date: date)[0]
        let failedCard = MinesweeperDailyCard(entry: entry, isCompleted: false, isFailed: true)
        viewModel.cardTapped(failedCard)
        let scoredRoute = AppRoute.board(difficulty: entry.difficulty, seed: entry.seed, mode: .daily)
        #expect(path.first != scoredRoute)
    }

    @Test func bootstrapIsIdempotent() async {
        let counter = Counter()
        let counting = CountingProvider(onFetch: { counter.increment() })
        let viewModel = MinesweeperDailyHubViewModel(path: .constant([]), provider: counting)
        await viewModel.bootstrap()
        await viewModel.bootstrap()
        #expect(counter.value == 1)
    }
}

// MARK: - Fakes

private struct CountingProvider: MinesweeperDailyProviding {
    let onFetch: @Sendable () -> Void
    func dailyTrio(date: Date) -> [MinesweeperDailyEntry] {
        onFetch()
        return LiveMinesweeperDailyProvider().dailyTrio(date: date)
    }
}

/// Tiny thread-safe counter for the idempotency assertion.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
