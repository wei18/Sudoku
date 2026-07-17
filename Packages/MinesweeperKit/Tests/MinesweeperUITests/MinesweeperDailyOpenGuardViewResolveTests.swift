// MinesweeperDailyOpenGuardViewResolveTests — #842.
//
// `MinesweeperDailyOpenGuardView.resolve` is the airtight (correctness) half
// of the #842 defense-in-depth fix: `MinesweeperDailyHubViewModel.cardTapped`
// decides completed/failed/playable from the tapped card's phase-1-stale
// flags (`false`/`false` until `fillCompletionAndFailureOverlay` — phase 2 —
// lands, #530/#774), so a fast tap on an actually completed-or-failed daily
// used to reach the scored `.board(mode: .daily)` route regardless: a loss
// there re-derives a DIFFERENT mine layout than the original failed attempt
// (#841) and overwrites the real Failed record; a win double-submits a GC
// score. `resolve` is the ONE seam every `.board(mode: .daily)` mount funnels
// through (LiveRouteFactory wraps it whenever `savedGameStore` is wired), so
// fixing it here is race-proof by construction.
//
// Round 2 (adversarial CR): a fetch FAILURE during `resolve` must degrade to
// the normal (local-first) mount — `.playable` — never a blocking error
// screen. Mirrors the #526 guarantee `MinesweeperDailyHubViewModelOfflineTests`
// already pins for the hub's own phase-2 fetch ("CloudKit unreachable must
// never block daily play") and Sudoku's same-round `BoardLoaderView
// .dailyPrecheck` adjudication. An earlier version of `resolve` instead
// returned `.checkFailed` (a blocking error screen) on fetch failure — that
// inverted #526 for EVERY daily open, not just the #842 race window, and was
// rejected on review.
//
// These tests drive `resolve` directly (no SwiftUI view tree needed — it is
// `static` and decoupled from `@State`) so a gated/hanging fetch and its
// eventual resolution are both deterministically observable. Gateway fakes
// mirror `MinesweeperDailyHubViewModelOfflineTests`'s established technique
// (a `PrivateCKGateway` conformer wrapped in a real `MinesweeperSavedGameStore`
// — the store is a concrete actor with no protocol seam of its own).

import Foundation
import Testing
import MinesweeperEngine
import MinesweeperPersistence
import Persistence
import PersistenceTesting
import Telemetry
@testable import MinesweeperUI

@MainActor
@Suite("MinesweeperDailyOpenGuardView.resolve (#842)")
struct MinesweeperDailyOpenGuardViewResolveTests {

    nonisolated(unsafe) private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    private func dailyRecordPayload(recordName: String, status: String) -> RecordPayload {
        RecordPayload(
            recordType: PrivateCKConstants.savedGameRecordType,
            recordName: recordName,
            fields: [
                "difficulty": .string("beginner"),
                "seed": .int(0),
                "mode": .string("daily"),
                "elapsedSeconds": .int(30),
                "status": .string(status),
                "lastModifiedAt": .date(Self.fixedDate),
                "schemaVersion": .int(1),
                "stateBlob": .data(Data()),
            ]
        )
    }

    // MARK: - Confirmed-completed → `.completed`, never a scored board

    @Test func completedRecordResolvesToCompleted() async {
        let recordName = MinesweeperSavedGameStore.recordName(
            mode: .daily, difficulty: .beginner, now: Self.fixedDate
        )
        let gateway = FakePrivateCKGateway()
        await gateway.seed(dailyRecordPayload(recordName: recordName, status: "completed"))
        let store = MinesweeperSavedGameStore(gateway: gateway, clock: { Self.fixedDate })

        let outcome = await MinesweeperDailyOpenGuardView.resolve(
            recordName: recordName, date: Self.fixedDate, store: store, errorReporter: nil
        )

        #expect(outcome == .completed)
    }

    // MARK: - Confirmed-failed → `.failed` (delegates to the #841 fixed replay)

    @Test func failedRecordResolvesToFailed() async {
        let recordName = MinesweeperSavedGameStore.recordName(
            mode: .daily, difficulty: .beginner, now: Self.fixedDate
        )
        let gateway = FakePrivateCKGateway()
        await gateway.seed(dailyRecordPayload(recordName: recordName, status: "failed"))
        let store = MinesweeperSavedGameStore(gateway: gateway, clock: { Self.fixedDate })

        let outcome = await MinesweeperDailyOpenGuardView.resolve(
            recordName: recordName, date: Self.fixedDate, store: store, errorReporter: nil
        )

        #expect(outcome == .failed)
    }

    // MARK: - Neither → `.playable` (never played yet, or a different day)

    @Test func neverPlayedRecordResolvesToPlayable() async {
        let recordName = MinesweeperSavedGameStore.recordName(
            mode: .daily, difficulty: .beginner, now: Self.fixedDate
        )
        let gateway = FakePrivateCKGateway()
        let store = MinesweeperSavedGameStore(gateway: gateway, clock: { Self.fixedDate })

        let outcome = await MinesweeperDailyOpenGuardView.resolve(
            recordName: recordName, date: Self.fixedDate, store: store, errorReporter: nil
        )

        #expect(outcome == .playable)
    }

    // MARK: - #526 adjudication: a fetch FAILURE degrades to `.playable`,
    // never blocks — mirrors the hub's own local-first phase-2 contract.

    @Test func fetchFailureDegradesToPlayableWithExactlyOneTelemetryReport() async {
        let recordName = MinesweeperSavedGameStore.recordName(
            mode: .daily, difficulty: .beginner, now: Self.fixedDate
        )
        let store = MinesweeperSavedGameStore(
            gateway: ThrowingQueryGateway(error: PersistenceError.iCloudNotSignedIn),
            clock: { Self.fixedDate }
        )
        let reporter = RecordingErrorReporter()

        let outcome = await MinesweeperDailyOpenGuardView.resolve(
            recordName: recordName, date: Self.fixedDate, store: store, errorReporter: reporter
        )

        #expect(outcome == .playable)
        #expect(await reporter.reportCount == 1)
    }

    // MARK: - Gated/hanging fetch: the outcome cannot resolve early

    @Test func gatedFetchDoesNotResolveUntilTheStoreAnswers() async {
        let recordName = MinesweeperSavedGameStore.recordName(
            mode: .daily, difficulty: .beginner, now: Self.fixedDate
        )
        let gated = GatedQueryGateway()
        let store = MinesweeperSavedGameStore(gateway: gated, clock: { Self.fixedDate })

        let task = Task {
            await MinesweeperDailyOpenGuardView.resolve(
                recordName: recordName, date: Self.fixedDate, store: store, errorReporter: nil
            )
        }

        // "Immediate tap while the open-time re-check is in flight": nothing
        // observable happens until the store actually answers.
        for _ in 0..<50 {
            await Task.yield()
        }
        #expect(await gated.awaitingResolution)

        await gated.resolve(.success([dailyRecordPayload(recordName: recordName, status: "completed")]))

        let outcome = await task.value
        #expect(outcome == .completed)
    }

    /// A gated fetch that eventually FAILS (rather than hanging forever) must
    /// still resolve — to `.playable`, with one report — never left
    /// unresolved and never surfaced as a blocking error.
    @Test func gatedFetchFailureAfterHangingDegradesToPlayable() async {
        let recordName = MinesweeperSavedGameStore.recordName(
            mode: .daily, difficulty: .beginner, now: Self.fixedDate
        )
        let gated = GatedQueryGateway()
        let store = MinesweeperSavedGameStore(gateway: gated, clock: { Self.fixedDate })
        let reporter = RecordingErrorReporter()

        let task = Task {
            await MinesweeperDailyOpenGuardView.resolve(
                recordName: recordName, date: Self.fixedDate, store: store, errorReporter: reporter
            )
        }
        for _ in 0..<50 {
            await Task.yield()
        }

        await gated.resolve(.failure(PersistenceError.iCloudNotSignedIn))

        let outcome = await task.value
        #expect(outcome == .playable)
        #expect(await reporter.reportCount == 1)
    }
}

// MARK: - Fakes

/// Gateway fake whose `query` throws immediately — mirrors
/// `MinesweeperDailyHubViewModelOfflineTests.ThrowingQueryGateway` (kept
/// file-local rather than shared: same rationale as that precedent, a 6-line
/// fake not worth promoting to shared test infra).
private actor ThrowingQueryGateway: PrivateCKGateway {
    private let error: any Error & Sendable
    init(error: any Error & Sendable) { self.error = error }
    func provisionZone() async throws {}
    func installSubscriptionIfNeeded() async throws {}
    func fetch(recordName: String) async throws -> RecordPayload? { nil }
    func save(_ payload: RecordPayload, policy: RecordSavePolicy) async throws {}
    func delete(recordName: String) async throws {}
    func query(_ predicate: RecordPredicate) async throws -> [RecordPayload] {
        throw error
    }
}

/// Gateway fake whose `query` hangs on a manually resolved continuation —
/// simulates a CloudKit fetch that has not answered yet, so a test can assert
/// nothing resolves before the caller decides to let it through (#842:
/// "gated/hanging completion fetch").
private actor GatedQueryGateway: PrivateCKGateway {
    private var continuation: CheckedContinuation<[RecordPayload], Error>?
    private(set) var awaitingResolution = false

    func resolve(_ result: Result<[RecordPayload], Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }

    func provisionZone() async throws {}
    func installSubscriptionIfNeeded() async throws {}
    func fetch(recordName: String) async throws -> RecordPayload? { nil }
    func save(_ payload: RecordPayload, policy: RecordSavePolicy) async throws {}
    func delete(recordName: String) async throws {}

    func query(_ predicate: RecordPredicate) async throws -> [RecordPayload] {
        awaitingResolution = true
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }
}

/// Records `report(_:underlying:source:)` calls so the honest-failure test can
/// assert the error was funneled rather than silently swallowed.
private actor RecordingErrorReporter: ErrorReporter {
    private(set) var reportCount = 0
    func report(_ error: UserFacingError, underlying: any Error, source: String) {
        reportCount += 1
    }
}
