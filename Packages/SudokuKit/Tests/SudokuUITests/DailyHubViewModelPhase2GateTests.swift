// DailyHubViewModelPhase2GateTests — #842 tap-gate (the UX-responsiveness
// half of the defense-in-depth pair; `BoardLoaderViewDailyPrecheckTests`
// covers the correctness half).
//
// `cardTapped` used to route purely off the tapped `DailyCard`'s
// (phase-1-stale) `isCompleted` flag with no notion of "phase 2 hasn't landed
// yet". While `isPhase2Pending`, a tap now no-ops instead of pushing a route
// off data that might be wrong — avoids a wasted/flickering navigation even
// though `BoardLoaderView`'s own precheck (#842) would still land on the
// correct surface regardless.

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

    @Test func cardTapNoOpsWhilePhase2FetchIsGatedThenWorksOnceItLands() async {
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

        viewModel.cardTapped(cards[0])
        #expect(box.routes.isEmpty)

        await gated.unlock()
        await bootstrapTask.value

        #expect(viewModel.isPhase2Pending == false)

        viewModel.cardTapped(cards[0])
        #expect(box.routes == [.board(puzzleId: cards[0].envelope.identity.puzzleId)])
    }

    /// `refresh()` re-arms the SAME gate (not just `bootstrap()`'s first run)
    /// — a tap landing during a post-solve `refresh()` re-fetch must also
    /// no-op, not just the very first hub load.
    @Test func cardTapNoOpsDuringARefreshReentryToo() async {
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
        #expect(box.routes.isEmpty)

        await gated.unlock()
        await refreshTask.value
        #expect(viewModel.isPhase2Pending == false)
    }
}

// MARK: - GatedWeekWindowPersistence

/// A `PersistenceProtocol` conformer whose `fetchCompletedDailyIds` hangs on
/// a manually resolved continuation until `unlock()` is called — simulates
/// the hub's phase-2 (week-strip) fetch never having answered yet. `relock()`
/// re-arms the gate for a second (e.g. `refresh()`) run.
private actor GatedWeekWindowPersistence: PersistenceProtocol {
    private var continuation: CheckedContinuation<Set<String>, Never>?
    private var unlocked = false

    func unlock() {
        unlocked = true
        continuation?.resume(returning: [])
        continuation = nil
    }

    func relock() {
        unlocked = false
    }

    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> {
        if unlocked { return [] }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

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
