// GameRootViewModelTabPathTests — the #1020 per-tab navigation contracts.
//
// design.md §3.6.2, quoted verbatim on `GameRootViewModel.setPath(_:for:_:)`:
//
//   Resume pill refresh triggers = ① ANY tab's path shortening (not just the
//   current tab) ∪ ② dismissGame() (iOS cover collapse) ∪ ③ bootstrap()
//   (launch). Switching tabs itself does NOT trigger refresh — a tab switch is
//   not a pop, no game session ended.
//
// Both halves get a test: C-34 is the positive guard for ①, N-AB the negative
// guard that a tab switch stays inert. ② and ③ are already covered by
// `GameRootViewModelTests`.

import Foundation
import Testing
import GameCenterClient
import GameShellUI
import SudokuGameState
import Persistence
import SudokuEngine
import Telemetry
@testable import GameAppKit

// MARK: - Test route

private enum TabRoute: Hashable, Sendable {
    case board(puzzleId: String)
    case settings
}

// MARK: - Fakes

private actor TabStubPersistence: PersistenceProtocol {
    func bootstrap() async throws {}
    func latestInProgress() async throws -> SavedGameSummary? { nil }
    func loadOrCreate(
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> GameSessionSnapshot {
        throw PersistenceError.zoneNotProvisioned
    }
    func save(
        _ snapshot: GameSessionSnapshot,
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws {}
    func markCompleted(_ summary: SavedGameSummary) async throws {}
    func deleteAbandoned(recordName: String) async throws {}
    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> { [] }
    func fetchCompletedDailyIdsByDay() async throws -> [String: Set<String>] { [:] }
    func fetchPersonalRecord(mode: Mode, difficulty: Difficulty) async throws -> PersonalRecord {
        PersonalRecord(
            recordName: "",
            mode: .daily,
            difficulty: .easy,
            bestTimeSeconds: nil,
            totalTimeSeconds: 0,
            completedCount: 0,
            lastUpdatedAt: Date(timeIntervalSince1970: 0),
            completedPuzzleIds: []
        )
    }
    func upsertPersonalRecord(_ record: PersonalRecord) async throws {}
}

private struct TabStubGameCenter: GameCenterClient {
    func authenticate() async throws -> GameCenterAuthState { .unauthenticated }
    func authStateUpdates() async -> AsyncStream<GameCenterAuthState> {
        AsyncStream { $0.finish() }
    }
    func submitScore(
        puzzleId: String,
        elapsedSeconds: Int,
        leaderboardKind: LeaderboardKind
    ) async throws {}
    func submitScore(leaderboardId: String, elapsedSeconds: Int) async throws {}
    func reportAchievement(_ achievement: AchievementProgress) async throws {}
}

/// Counts how many times the injected resume fetch actually ran — the signal
/// both contracts below are stated in terms of.
private actor FetchCounter {
    private(set) var count = 0
    func fetch() -> ResumeCandidate<TabRoute>? {
        count += 1
        return nil
    }
}

@MainActor
private func makeViewModel(
    counter: FetchCounter
) -> GameRootViewModel<TabRoute> {
    GameRootViewModel<TabRoute>(
        gameCenter: TabStubGameCenter(),
        persistence: TabStubPersistence(),
        fetchResume: { await counter.fetch() }
    )
}

/// `setPath`'s refresh runs in an unstructured `Task`; give it real time to
/// land. Bare `Task.yield()` loops are not enough under the parallel test
/// runner (the refresh Task can stay unscheduled for all 20 yields, ~1 in 3
/// runs), so each turn also sleeps a millisecond.
private func settle() async {
    for _ in 0..<20 {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(1))
    }
}

// MARK: - Suite

@Suite("GameAppKit — GameRootViewModel per-tab paths (#1020)")
@MainActor
struct GameRootViewModelTabPathTests {

    @Test("every tab starts at its root")
    func everyTabStartsEmpty() async {
        let viewModel = makeViewModel(counter: FetchCounter())

        #expect(viewModel.selectedTab == .today)
        #expect(AppTab.allCases.allSatisfy { viewModel.path(for: $0).isEmpty })
    }

    @Test("each tab's stack is independent")
    func tabsHoldIndependentStacks() async {
        let viewModel = makeViewModel(counter: FetchCounter())

        viewModel.setPath([.settings], for: .today)
        viewModel.setPath([.board(puzzleId: "p1")], for: .practice)

        #expect(viewModel.path(for: .today) == [.settings])
        #expect(viewModel.path(for: .practice) == [.board(puzzleId: "p1")])
        #expect(viewModel.path(for: .progress).isEmpty)
    }

    @Test("push lands on the selected tab, not a fixed one")
    func pushTargetsTheSelectedTab() async {
        let viewModel = makeViewModel(counter: FetchCounter())
        viewModel.selectedTab = .progress

        viewModel.push(.settings)

        #expect(viewModel.path(for: .progress) == [.settings])
        #expect(viewModel.path(for: .today).isEmpty)
    }

    // MARK: - C-34: refresh on ANY tab's shrink

    /// The bug this contract exists to prevent: complete a game in Practice,
    /// switch to Today, and the resume pill is stale. Pre-#1020 the shrink
    /// detection was keyed on the ONE visible path, so a pop in a tab the
    /// player was not looking at went unnoticed.
    ///
    /// Here the selected tab stays `.today` throughout — the shrink happens in
    /// `.practice` and must still refresh.
    @Test("C-34: a NON-current tab's pop refreshes the resume pill")
    func shrinkOnNonCurrentTabTriggersRefresh() async {
        let counter = FetchCounter()
        let viewModel = makeViewModel(counter: counter)
        await viewModel.bootstrap()
        await settle()

        let afterBootstrap = await counter.count
        let teardownsAfterBootstrap = viewModel.sessionTeardownCount

        viewModel.setPath([.board(puzzleId: "p1")], for: .practice)
        await settle()
        // Growth must not refresh — only a shrink means a session ended.
        #expect(await counter.count == afterBootstrap)
        #expect(viewModel.sessionTeardownCount == teardownsAfterBootstrap)

        viewModel.setPath([], for: .practice)
        await settle()

        #expect(viewModel.selectedTab == .today, "the shrink was in a tab the player is NOT looking at")
        #expect(await counter.count == afterBootstrap + 1)
        #expect(viewModel.sessionTeardownCount == teardownsAfterBootstrap + 1)
    }

    @Test("growth on any tab does not refresh")
    func growthNeverRefreshes() async {
        let counter = FetchCounter()
        let viewModel = makeViewModel(counter: counter)
        await viewModel.bootstrap()
        await settle()
        let baseline = await counter.count

        for tab in AppTab.allCases {
            viewModel.setPath([.settings], for: tab)
            viewModel.setPath([.settings, .board(puzzleId: "p1")], for: tab)
        }
        await settle()

        #expect(await counter.count == baseline)
        #expect(viewModel.sessionTeardownCount == 0)
    }

    /// #912 preserved: on iOS `GameBoardRedirect` pops its synthetic push entry
    /// at board OPEN, which shrinks a path exactly like a close does. That case
    /// is filtered by `isGamePresented`, and moving shrink detection from
    /// `GameRoot`'s binding setter into `setPath` must not have lost the filter.
    @Test("#912: a shrink while a game is presented is still filtered out")
    func shrinkWhileGamePresentedIsFiltered() async {
        let counter = FetchCounter()
        let viewModel = makeViewModel(counter: counter)
        await viewModel.bootstrap()
        await settle()
        let baseline = await counter.count

        viewModel.setPath([.board(puzzleId: "p1")], for: .today)
        viewModel.presentGame(route: .board(puzzleId: "p1"))
        viewModel.setPath([], for: .today) // the redirect's open-time pop
        await settle()

        #expect(await counter.count == baseline)
        #expect(viewModel.sessionTeardownCount == 0)
    }

    // MARK: - N-AB: switching tabs is not a pop

    /// Negative-flow contract, not an oversight: a tab switch ends no game
    /// session, so it must not reach `refreshResumeCandidate()` — and
    /// `selectedTab` stays a plain stored property precisely so it cannot.
    @Test("N-AB: switching tabs alone never refreshes or tears down")
    func switchingTabsDoesNotRefresh() async {
        let counter = FetchCounter()
        let viewModel = makeViewModel(counter: counter)
        await viewModel.bootstrap()
        await settle()

        // Populate every tab first: the contract must hold with real stacks in
        // place, not just from a pristine launch state.
        viewModel.setPath([.settings], for: .today)
        viewModel.setPath([.board(puzzleId: "p1")], for: .practice)
        viewModel.setPath([.settings], for: .progress)
        await settle()
        let baseline = await counter.count
        let teardowns = viewModel.sessionTeardownCount

        viewModel.selectedTab = .practice
        viewModel.selectedTab = .progress
        viewModel.selectedTab = .today
        await settle()

        #expect(await counter.count == baseline)
        #expect(viewModel.sessionTeardownCount == teardowns)
        // ...and the stacks survive the round trip.
        #expect(viewModel.path(for: .today) == [.settings])
        #expect(viewModel.path(for: .practice) == [.board(puzzleId: "p1")])
        #expect(viewModel.path(for: .progress) == [.settings])
    }

    @Test("popToRoot counts as a shrink")
    func popToRootRefreshes() async {
        let counter = FetchCounter()
        let viewModel = makeViewModel(counter: counter)
        await viewModel.bootstrap()
        await settle()
        viewModel.setPath([.board(puzzleId: "p1")], for: .practice)
        await settle()
        let baseline = await counter.count

        viewModel.popToRoot(of: .practice)
        await settle()

        #expect(await counter.count == baseline + 1)
        #expect(viewModel.path(for: .practice).isEmpty)
    }
}
