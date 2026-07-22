// MinesweeperDailyHubViewModelPhase2GateTests — #941 optimistic tap-enable,
// reversing #842's tap gate (`MinesweeperDailyOpenGuardViewResolveTests`
// covers the correctness half this reversal still relies on).
//
// `cardTapped` used to no-op while `isPhase2Pending` — the tapped card's
// (phase-1-stale) `isCompleted`/`isFailed` flags were considered too
// unreliable to route off. #941 (owner-requested) removed that gate: a tap
// now routes immediately off whatever the card currently says, even
// mid-fetch. Safe because `MinesweeperDailyOpenGuardView`'s own re-check
// (#842) unconditionally re-checks persistence on every daily open — the gate
// was only ever the UX-responsiveness half of a defense-in-depth pair, never
// the correctness guarantee.

import Foundation
import SwiftUI
import Testing
import MinesweeperEngine
import MinesweeperPersistence
import Persistence
import PersistenceTesting
@testable import MinesweeperUI

@MainActor
@Suite("MinesweeperDailyHubViewModel — phase-2-pending tap gate (#842)")
struct MinesweeperDailyHubViewModelPhase2GateTests {

    nonisolated(unsafe) private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    @Test func cardTapAppendsBoardRouteWhilePhase2PendingThenStillWorksOnceLanded() async {
        let gated = GatedQueryGateway()
        let store = MinesweeperSavedGameStore(gateway: gated, clock: { Self.fixedDate })
        var path: [AppRoute] = []
        let binding = Binding<[AppRoute]>(get: { path }, set: { path = $0 })
        let viewModel = MinesweeperDailyHubViewModel(
            path: binding,
            savedGameStore: store,
            dateProvider: { Self.fixedDate }
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
        #expect(path == [.board(difficulty: cards[0].difficulty, seed: cards[0].seed, mode: .daily)])

        await gated.resolve(.success([]))
        await bootstrapTask.value

        #expect(viewModel.isPhase2Pending == false)

        viewModel.cardTapped(cards[0])
        #expect(path == [
            .board(difficulty: cards[0].difficulty, seed: cards[0].seed, mode: .daily),
            .board(difficulty: cards[0].difficulty, seed: cards[0].seed, mode: .daily)
        ])
    }

    /// #886 CR round 2 regression guard: TWO concurrent `query()` calls
    /// landing before `resolve(_:)` must BOTH unblock — not orphan the
    /// first — the exact scenario a round-1 `async let` attempt at
    /// parallelizing the new best-time fetch hit when `GatedQueryGateway`
    /// stored only a single continuation (silently overwritten by the
    /// second call, leaking the first forever). Exercises the fake directly
    /// rather than through the view model, since production's `fetchBestTimes`
    /// reads through a different gateway method (`fetch(recordName:)`, not
    /// `query(_:)`) and would never race `fetchWeekWindow`/`fetchFailedIds`
    /// on the SAME method — this test proves the fake itself is now
    /// concurrency-safe regardless of which call sites end up racing it.
    @Test func gatedGatewayResumesAllConcurrentQueriesOnSingleResolve() async throws {
        let gated = GatedQueryGateway()
        async let first = gated.query(.all(recordType: "SavedGame"))
        async let second = gated.query(.all(recordType: "SavedGame"))
        // Give both calls a chance to reach the gate and register their own
        // continuation before resolving — without this, `resolve` could race
        // ahead of one call's registration and this test would pass for the
        // wrong reason (only ever gating one call).
        for _ in 0..<50 {
            await Task.yield()
        }
        await gated.resolve(.success([]))
        let firstResult = try await first
        let secondResult = try await second
        #expect(firstResult.isEmpty)
        #expect(secondResult.isEmpty)
    }

    /// #915: `fetchWeekWindow` now backs its whole 7-day window from ONE
    /// `fetchCompletedDailyIdsByDay()` call instead of #912's 7-way
    /// concurrent-but-redundant fan-out (7 byte-identical `query()` calls,
    /// each thrown away except its own day's slice). `fetchFailedIds` (an
    /// independent `async let` lane) still issues its own single `query()`
    /// call through the same gate, so `callCount` settles at 2 — not the
    /// pre-fix 8 — while both are still gated.
    @Test func weekWindowFetchIssuesExactlyOneQueryPlusOneFailedIdsQuery() async {
        let gated = GatedQueryGateway()
        let store = MinesweeperSavedGameStore(gateway: gated, clock: { Self.fixedDate })
        var path: [AppRoute] = []
        let binding = Binding<[AppRoute]>(get: { path }, set: { path = $0 })
        let viewModel = MinesweeperDailyHubViewModel(
            path: binding,
            savedGameStore: store,
            dateProvider: { Self.fixedDate }
        )

        let bootstrapTask = Task { await viewModel.bootstrap() }
        for _ in 0..<200 {
            await Task.yield()
        }

        #expect(await gated.callCount == 2)

        await gated.resolve(.success([]))
        await bootstrapTask.value

        // Ordering is preserved: oldest (offset 6) first, today (offset 0)
        // last — `MinesweeperDailyStripView` depends on this order.
        #expect(viewModel.weekStrip.days.map(\.offsetFromToday) == [6, 5, 4, 3, 2, 1, 0])
    }
}

/// Gateway fake whose `query` hangs on a manually resolved continuation UNTIL
/// `resolve(_:)` is called, after which the gate stays permanently open (every
/// later `query` call returns immediately). One-shot-unlock, unlike
/// `MinesweeperDailyOpenGuardViewResolveTests.GatedQueryGateway`, which only
/// needs to gate a SINGLE call (`resolve`'s correctness check short-circuits
/// after the first query); this suite's `fillCompletionAndFailureOverlay`
/// makes several sequential query calls that must all resolve once the phase-2
/// window is "unblocked".
///
/// #886 CR round 2: `continuation` used to be a SINGLE stored
/// `CheckedContinuation` — if two `query()` calls landed before `resolve(_:)`,
/// the second overwrote the first, silently ORPHANING it forever ("SWIFT TASK
/// CONTINUATION MISUSE: leaked its continuation without resuming it" /
/// deadlock). That was a limitation of this fake, not of production
/// `PrivateCKGateway` conformers (plain actors — concurrent calls just
/// serialize at the actor's mailbox, each with its own continuation). Now a
/// queue: every pending call gets its own slot, and `resolve(_:)` drains and
/// resumes ALL of them, so concurrent `query()` calls (e.g. two `async let`
/// lanes racing through the same gateway) are exercised honestly instead of
/// silently hanging.
private actor GatedQueryGateway: PrivateCKGateway {
    private var pendingContinuations: [CheckedContinuation<[RecordPayload], Error>] = []
    private var unlockedResult: Result<[RecordPayload], Error>?
    /// #912/#915: counts every `query()` invocation (gated or not). See
    /// `weekWindowFetchIssuesExactlyOneQueryPlusOneFailedIdsQuery`.
    private(set) var callCount = 0

    func resolve(_ result: Result<[RecordPayload], Error>) {
        unlockedResult = result
        let waiting = pendingContinuations
        pendingContinuations = []
        for continuation in waiting {
            continuation.resume(with: result)
        }
    }

    func provisionZone() async throws {}
    func installSubscriptionIfNeeded() async throws {}
    func fetch(recordName: String) async throws -> RecordPayload? { nil }
    func save(_ payload: RecordPayload, policy: RecordSavePolicy) async throws {}
    func delete(recordName: String) async throws {}

    func query(_ predicate: RecordPredicate) async throws -> [RecordPayload] {
        callCount += 1
        if let unlockedResult { return try unlockedResult.get() }
        return try await withCheckedThrowingContinuation { continuation in
            self.pendingContinuations.append(continuation)
        }
    }
}
