// BoardLoaderViewDailyPrecheckTests — #842.
//
// `BoardLoaderView.dailyPrecheck` is the airtight (correctness) half of the
// #842 defense-in-depth fix: `DailyHubViewModel.cardTapped`'s not-completed
// branch pushes `.board(puzzleId:)` on phase-1-stale `card.isCompleted` data
// (`false` until the hub's phase-2 overlay fetch lands, #530/#774) — so a fast
// tap on an actually-completed daily used to reach `BoardLoaderView` and mount
// a fully playable board (timer restarts, replayable). `dailyPrecheck` is the
// ONE seam every `.board` mount funnels through regardless of caller, so
// fixing it here is race-proof by construction (mirrors
// `MinesweeperDailyReplayLoaderView.makeReplaySession`'s testable-core shape
// for the sibling #841 issue).
//
// Round 2 (adversarial CR): a fetch FAILURE during the precheck must degrade
// to the normal (local-first) mount, never a blocking error screen — mirrors
// the #526 guarantee `DailyHubViewModelOfflineTests` already pins for the
// hub's own phase-2 fetch, and `SavedGameStore.loadOrCreate`'s own documented
// "iCloud unavailability must never prevent puzzle load" contract. An earlier
// version of this precheck threw on fetch failure so `load()` landed on
// `.failed` — that inverted #526 for EVERY daily open, not just the race
// window, and was rejected on review.
//
// These tests drive `dailyPrecheck` directly (no SwiftUI view tree needed —
// it is `static` and decoupled from `@State`) so a gated/hanging fetch and its
// eventual resolution are both deterministically observable.

import Foundation
import Testing
@testable import SudokuUI

import SudokuGameState
import Persistence
import SudokuPersistence
import SudokuEngine
import SudokuKitTesting
import Telemetry

@MainActor
@Suite("BoardLoaderView.dailyPrecheck (#842)")
struct BoardLoaderViewDailyPrecheckTests {

    private static let dailyIdentity = PuzzleIdentity(
        puzzleId: "2026-05-21-easy", kind: .daily, difficulty: .easy
    )

    private func snapshot(status: GameSessionStatus, elapsedSeconds: Int = 742, mistakeCount: Int = 2) -> GameSessionSnapshot {
        let puzzle = FakePuzzleProvider.defaultPuzzle(difficulty: .easy, seed: 1)
        return GameSessionSnapshot(
            puzzle: puzzle,
            currentBoard: puzzle.solution,
            status: status,
            elapsedSeconds: elapsedSeconds,
            undoMoves: [],
            redoMoves: [],
            notes: NotesGrid(),
            mistakeCount: mistakeCount
        )
    }

    // MARK: - Confirmed-completed → `.completed`, never a playable board

    @Test func completedRecordResolvesToCompletedOutcomeWithFrozenTime() async {
        let persistence = FakePersistence()
        await persistence.setLoadOrCreateSnapshot(snapshot(status: .completed, elapsedSeconds: 742, mistakeCount: 2))
        let reporter = RecordingErrorReporter()

        let outcome = await BoardLoaderView.dailyPrecheck(
            puzzleId: Self.dailyIdentity.puzzleId,
            identity: Self.dailyIdentity,
            persistence: persistence,
            errorReporter: reporter
        )

        guard case .completed(let cvm) = outcome else {
            Issue.record("expected .completed, got \(outcome)")
            return
        }
        #expect(cvm.elapsedSeconds == 742)
        #expect(cvm.mistakeCount == 2)
        #expect(cvm.puzzleId == Self.dailyIdentity.puzzleId)
        #expect(await reporter.reportCount == 0)
    }

    // MARK: - In-progress record → `.notCompleted`, reused (no 2nd fetch)

    @Test func inProgressRecordResolvesToNotCompletedCarryingTheSnapshot() async {
        let persistence = FakePersistence()
        await persistence.setLoadOrCreateSnapshot(snapshot(status: .paused, elapsedSeconds: 30))

        let outcome = await BoardLoaderView.dailyPrecheck(
            puzzleId: Self.dailyIdentity.puzzleId,
            identity: Self.dailyIdentity,
            persistence: persistence,
            errorReporter: RecordingErrorReporter()
        )

        guard case .notCompleted(let existing) = outcome else {
            Issue.record("expected .notCompleted, got \(outcome)")
            return
        }
        #expect(existing.status == .paused)
        #expect(existing.elapsedSeconds == 30)
    }

    // MARK: - Confirmed absence (never played) → `.absent`

    @Test func neverPlayedRecordResolvesToAbsent() async {
        let persistence = FakePersistence()
        // No `loadOrCreateSnapshot` scripted, no error — `loadIfExists`
        // returns `nil` (confirmed absence), not the loud default throw.
        let reporter = RecordingErrorReporter()

        let outcome = await BoardLoaderView.dailyPrecheck(
            puzzleId: Self.dailyIdentity.puzzleId,
            identity: Self.dailyIdentity,
            persistence: persistence,
            errorReporter: reporter
        )

        guard case .absent = outcome else {
            Issue.record("expected .absent, got \(outcome)")
            return
        }
        // Confirmed absence is not an error — no report.
        #expect(await reporter.reportCount == 0)
    }

    // MARK: - #526 adjudication: a fetch FAILURE degrades to `.absent`,
    // never blocks — mirrors `loadOrCreate`'s own local-first contract.

    @Test func fetchFailureDegradesToAbsentWithExactlyOneTelemetryReport() async {
        let persistence = FakePersistence()
        await persistence.setLoadOrCreateError(.zoneNotProvisioned)
        let reporter = RecordingErrorReporter()

        let outcome = await BoardLoaderView.dailyPrecheck(
            puzzleId: Self.dailyIdentity.puzzleId,
            identity: Self.dailyIdentity,
            persistence: persistence,
            errorReporter: reporter
        )

        guard case .absent = outcome else {
            Issue.record("expected .absent (never a blocking error), got \(outcome)")
            return
        }
        #expect(await reporter.reportCount == 1)
    }

    // MARK: - Gated/hanging fetch: the outcome cannot resolve early

    @Test func gatedFetchDoesNotResolveUntilPersistenceAnswers() async {
        let gated = GatedDailyPersistence()
        let task = Task {
            await BoardLoaderView.dailyPrecheck(
                puzzleId: Self.dailyIdentity.puzzleId,
                identity: Self.dailyIdentity,
                persistence: gated,
                errorReporter: RecordingErrorReporter()
            )
        }

        // Spin a bounded number of yields — the task must NOT have produced a
        // result yet (the fetch is still gated). This is the "immediate tap
        // while phase-2 / the open-time fetch is in flight" scenario: nothing
        // observable happens until the store actually answers.
        for _ in 0..<50 {
            await Task.yield()
        }
        #expect(await gated.awaitingResolution)

        await gated.resolve(.success(snapshot(status: .completed, elapsedSeconds: 99, mistakeCount: 0)))

        let outcome = await task.value
        guard case .completed(let cvm) = outcome else {
            Issue.record("expected .completed once the gate resolved, got \(outcome)")
            return
        }
        #expect(cvm.elapsedSeconds == 99)
    }

    /// A gated fetch that eventually FAILS (rather than hanging forever)
    /// must still resolve — to `.absent`, with one report — never left
    /// unresolved and never surfaced as a blocking error.
    @Test func gatedFetchFailureAfterHangingDegradesToAbsent() async {
        let gated = GatedDailyPersistence()
        let reporter = RecordingErrorReporter()
        let task = Task {
            await BoardLoaderView.dailyPrecheck(
                puzzleId: Self.dailyIdentity.puzzleId,
                identity: Self.dailyIdentity,
                persistence: gated,
                errorReporter: reporter
            )
        }
        for _ in 0..<50 {
            await Task.yield()
        }

        await gated.resolve(.failure(PersistenceError.zoneNotProvisioned))

        let outcome = await task.value
        guard case .absent = outcome else {
            Issue.record("expected .absent (never a blocking error), got \(outcome)")
            return
        }
        #expect(await reporter.reportCount == 1)
    }
}

// MARK: - GatedDailyPersistence

/// A `PersistenceProtocol` conformer whose `loadIfExists` hangs on a manually
/// resolved continuation — simulates a CloudKit fetch that has not answered
/// yet, so a test can assert nothing routes/resolves before the caller
/// decides to let it through (#842: "gated/hanging completion fetch").
private actor GatedDailyPersistence: PersistenceProtocol {
    private var continuation: CheckedContinuation<GameSessionSnapshot?, Error>?
    private(set) var awaitingResolution = false

    func resolve(_ result: Result<GameSessionSnapshot?, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }

    func bootstrap() async throws {}
    func latestInProgress() async throws -> SavedGameSummary? { nil }

    func loadOrCreate(puzzleId: String, mode: Mode, difficulty: Difficulty) async throws -> GameSessionSnapshot {
        fatalError("not exercised by these tests — dailyPrecheck only calls loadIfExists")
    }

    func loadIfExists(puzzleId: String, mode: Mode, difficulty: Difficulty) async throws -> GameSessionSnapshot? {
        awaitingResolution = true
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func save(_ snapshot: GameSessionSnapshot, puzzleId: String, mode: Mode, difficulty: Difficulty) async throws {}
    func markCompleted(_ summary: SavedGameSummary) async throws {}
    func deleteAbandoned(recordName: String) async throws {}
    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> { [] }
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

/// Records `report(_:underlying:source:)` calls so a test can assert an error
/// was funneled (or NOT funneled — confirmed absence is not an error) without
/// depending on a live errorReporter sink.
private actor RecordingErrorReporter: ErrorReporter {
    private(set) var reportCount = 0
    func report(_ error: UserFacingError, underlying: any Error, source: String) {
        reportCount += 1
    }
}
