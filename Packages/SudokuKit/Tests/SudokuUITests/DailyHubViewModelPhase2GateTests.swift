// DailyHubViewModelPhase2GateTests — #941 optimistic tap-enable, reversing
// #842's tap gate (`BoardLoaderViewDailyPrecheckTests` covers the correctness
// half this reversal still relies on).
//
// `cardTapped` used to no-op while `isPhase2Pending` — the tapped `DailyCard`'s
// (phase-1-stale) `isCompleted` flag was considered too unreliable to route
// off. #941 (owner-requested) removed that gate: a tap now routes immediately
// off whatever `card.isCompleted` currently says, appending the board route
// even mid-fetch. This is safe because `BoardLoaderView`'s own precheck (#842)
// unconditionally re-checks persistence on every daily open and redirects to
// Completion if already done — the gate was only ever the UX-responsiveness
// half of a defense-in-depth pair, never the correctness guarantee.

import Foundation
import Testing
@testable import SudokuUI

import SudokuGameState
import Persistence
import SudokuPersistence
import SudokuEngine
import SudokuKitTesting

@MainActor
@Suite("DailyHubViewModel — phase-2-pending tap gate (#842)")
struct DailyHubViewModelPhase2GateTests {

    nonisolated(unsafe) private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    @Test func cardTapAppendsBoardRouteWhilePhase2PendingThenStillWorksOnceLanded() async {
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)))
        let gated = GatedWeekWindowPersistence()
        let box = RoutePathBox()
        let viewModel = DailyHubViewModel(
            provider: provider,
            persistence: gated,
            dateProvider: { Self.fixedDate },
            path: box.binding
        )

        let bootstrapTask = Task { await viewModel.bootstrap() }
        // Let phase-1 land (state → `.loaded`) but keep phase-2's first
        // week-strip fetch gated — the "immediate tap while phase-2 is in
        // flight" scenario.
        for _ in 0..<200 {
            await Task.yield()
        }

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected .loaded before phase-2 lands, got \(viewModel.state)")
            bootstrapTask.cancel()
            return
        }
        #expect(viewModel.isPhase2Pending == true)

        // #941: a tap while phase-2 is still in flight appends the board
        // route immediately instead of no-opping — the phase-1 placeholder
        // card is un-completed, so this is the fresh-board path.
        viewModel.cardTapped(cards[0])
        #expect(box.routes == [.board(puzzleId: cards[0].envelope.identity.puzzleId)])

        await gated.unlock()
        await bootstrapTask.value

        #expect(viewModel.isPhase2Pending == false)

        viewModel.cardTapped(cards[0])
        #expect(box.routes == [
            .board(puzzleId: cards[0].envelope.identity.puzzleId),
            .board(puzzleId: cards[0].envelope.identity.puzzleId)
        ])
    }

    /// `refresh()` re-arms the SAME `isPhase2Pending` window (not just
    /// `bootstrap()`'s first run) — a tap landing during a post-solve
    /// `refresh()` re-fetch also appends the board route, not a no-op.
    @Test func cardTapAppendsBoardRouteDuringARefreshReentryToo() async {
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)))
        let gated = GatedWeekWindowPersistence()
        let box = RoutePathBox()
        let viewModel = DailyHubViewModel(
            provider: provider,
            persistence: gated,
            dateProvider: { Self.fixedDate },
            path: box.binding
        )

        await gated.unlock() // let bootstrap's own phase-2 resolve immediately
        await viewModel.bootstrap()
        #expect(viewModel.isPhase2Pending == false)

        await gated.relock()
        let refreshTask = Task { await viewModel.refresh() }
        for _ in 0..<200 {
            await Task.yield()
        }
        #expect(viewModel.isPhase2Pending == true)

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected .loaded, got \(viewModel.state)")
            refreshTask.cancel()
            return
        }
        viewModel.cardTapped(cards[1])
        #expect(box.routes == [.board(puzzleId: cards[1].envelope.identity.puzzleId)])

        await gated.unlock()
        await refreshTask.value
        #expect(viewModel.isPhase2Pending == false)
    }

    /// #921: `fetchWeekWindow` now backs its whole 7-day window from ONE
    /// `fetchCompletedDailyIdsByDay()` call instead of #912's 7-way
    /// concurrent-but-redundant fan-out (7 calls, each thrown away except its
    /// own day's slice). `callCount` settles at 1 while the single call is
    /// still gated.
    @Test func weekWindowFetchIssuesExactlyOneQuery() async {
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)))
        let gated = GatedWeekWindowPersistence()
        let viewModel = DailyHubViewModel(
            provider: provider,
            persistence: gated,
            dateProvider: { Self.fixedDate }
        )

        let bootstrapTask = Task { await viewModel.bootstrap() }
        for _ in 0..<200 {
            await Task.yield()
        }

        #expect(await gated.callCount == 1)

        await gated.unlock()
        await bootstrapTask.value

        // Ordering is preserved: oldest (offset 6) first, today (offset 0)
        // last — `DailyStripView` depends on this order.
        #expect(viewModel.weekStrip.days.map(\.offsetFromToday) == [6, 5, 4, 3, 2, 1, 0])
    }
}

// MARK: - GatedWeekWindowPersistence

/// A `PersistenceProtocol` conformer whose `fetchCompletedDailyIdsByDay`
/// hangs on a manually resolved continuation until `unlock()` is called —
/// simulates the hub's phase-2 (week-strip) fetch never having answered yet.
/// `relock()` re-arms the gate for a second (e.g. `refresh()`) run.
///
/// #921: gates `fetchCompletedDailyIdsByDay` (the single-query call
/// `fetchWeekWindow` now makes) rather than the old per-day
/// `fetchCompletedDailyIds` — `callCount` now proves exactly ONE query is
/// issued per window fetch (see `weekWindowFetchIssuesExactlyOneQuery`
/// below), where it used to prove 7 concurrent per-day calls (#912).
/// `pendingContinuations` stays a queue (not a single slot) for the same
/// leaked-continuation-safety reason #912 originally adopted it.
private actor GatedWeekWindowPersistence: PersistenceProtocol {
    private var pendingContinuations: [CheckedContinuation<[String: Set<String>], Never>] = []
    private var unlocked = false
    private(set) var callCount = 0

    func unlock() {
        unlocked = true
        let waiting = pendingContinuations
        pendingContinuations = []
        for continuation in waiting {
            continuation.resume(returning: [:])
        }
    }

    func relock() {
        unlocked = false
    }

    func fetchCompletedDailyIdsByDay() async throws -> [String: Set<String>] {
        callCount += 1
        if unlocked { return [:] }
        return await withCheckedContinuation { continuation in
            self.pendingContinuations.append(continuation)
        }
    }

    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> { [] }

    func bootstrap() async throws {}
    func latestInProgress() async throws -> SavedGameSummary? { nil }
    func loadOrCreate(puzzleId: String, mode: Mode, difficulty: Difficulty) async throws -> GameSessionSnapshot {
        fatalError("not exercised by these tests")
    }
    func save(_ snapshot: GameSessionSnapshot, puzzleId: String, mode: Mode, difficulty: Difficulty) async throws {}
    func markCompleted(_ summary: SavedGameSummary) async throws {}
    func deleteAbandoned(recordName: String) async throws {}
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
