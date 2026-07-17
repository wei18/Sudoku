// MinesweeperDailyHubViewModelPhase2GateTests — #842 tap-gate (the
// UX-responsiveness half of the defense-in-depth pair;
// `MinesweeperDailyOpenGuardViewResolveTests` covers the correctness half).
//
// `cardTapped` used to route purely off the tapped card's (phase-1-stale)
// `isCompleted`/`isFailed` flags with no notion of "phase 2 hasn't landed
// yet". While `isPhase2Pending`, a tap now no-ops instead of pushing a route
// off data that might be wrong — avoids a wasted navigation even though
// `MinesweeperDailyOpenGuardView`'s own re-check (#842) would still land on
// the correct surface regardless.

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

    @Test func cardTapNoOpsWhilePhase2FetchIsGatedThenWorksOnceItLands() async {
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

        viewModel.cardTapped(cards[0])
        #expect(path.isEmpty)

        await gated.resolve(.success([]))
        await bootstrapTask.value

        #expect(viewModel.isPhase2Pending == false)

        viewModel.cardTapped(cards[0])
        #expect(path == [.board(difficulty: cards[0].difficulty, seed: cards[0].seed, mode: .daily)])
    }
}

/// Gateway fake whose `query` hangs on a manually resolved continuation UNTIL
/// `resolve(_:)` is called, after which the gate stays permanently open (every
/// later `query` call — `fetchWeekWindow`'s 7 sequential days included —
/// returns immediately). One-shot-unlock, unlike
/// `MinesweeperDailyOpenGuardViewResolveTests.GatedQueryGateway`, which only
/// needs to gate a SINGLE call (`resolve`'s correctness check short-circuits
/// after the first query); this suite's `fillCompletionAndFailureOverlay`
/// makes several sequential query calls that must all resolve once the phase-2
/// window is "unblocked".
private actor GatedQueryGateway: PrivateCKGateway {
    private var continuation: CheckedContinuation<[RecordPayload], Error>?
    private var unlockedResult: Result<[RecordPayload], Error>?

    func resolve(_ result: Result<[RecordPayload], Error>) {
        unlockedResult = result
        continuation?.resume(with: result)
        continuation = nil
    }

    func provisionZone() async throws {}
    func installSubscriptionIfNeeded() async throws {}
    func fetch(recordName: String) async throws -> RecordPayload? { nil }
    func save(_ payload: RecordPayload, policy: RecordSavePolicy) async throws {}
    func delete(recordName: String) async throws {}

    func query(_ predicate: RecordPredicate) async throws -> [RecordPayload] {
        if let unlockedResult { return try unlockedResult.get() }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }
}
