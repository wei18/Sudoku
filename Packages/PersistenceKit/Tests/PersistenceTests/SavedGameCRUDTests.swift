// SavedGameCRUDTests — Phase 5.4: SavedGame CRUD via `FakePrivateCKGateway`.

import Foundation
import Testing
import GameState
import SudokuEngine
import Telemetry
import PersistenceTesting
import TelemetryTesting
@testable import Persistence

@Suite("Persistence — SavedGame CRUD")
struct SavedGameCRUDTests {

    private func makeStore(
        clock: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 1_000) }
    ) async -> (SavedGameStore, FakePrivateCKGateway, RecordingSink) {
        let gateway = FakePrivateCKGateway()
        let sink = RecordingSink()
        let telemetry = Telemetry(sinks: [sink])
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        let store = SavedGameStore(
            gateway: gateway,
            telemetry: telemetry,
            puzzleLoader: { _ in puzzle },
            clock: clock
        )
        return (store, gateway, sink)
    }

    @Test func loadOrCreateNewPuzzleSeedsFromGameState() async throws {
        let (store, gateway, _) = await makeStore()
        let snapshot = try await store.loadOrCreate(
            puzzleId: "2026-05-19-easy",
            mode: .daily,
            difficulty: .easy
        )
        #expect(snapshot.status == .idle)
        #expect(snapshot.elapsedSeconds == 0)
        #expect(snapshot.undoMoves.isEmpty)
        #expect(snapshot.redoMoves.isEmpty)
        // The freshly seeded record landed in the gateway.
        let count = await gateway.recordCount()
        #expect(count == 1)
    }

    @Test func saveRoundtrips() async throws {
        let (store, _, _) = await makeStore()
        // Build a non-trivial snapshot via GameSession.
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        let session = GameSession(puzzle: puzzle)
        try await session.start()
        try await session.placeDigit(row: 0, col: 0, digit: 1)
        let snapshot = await session.snapshot()

        try await store.save(
            snapshot,
            puzzleId: "p1",
            mode: .practice,
            difficulty: .easy
        )
        let loaded = try await store.loadOrCreate(
            puzzleId: "p1",
            mode: .practice,
            difficulty: .easy
        )
        #expect(loaded.currentBoard == snapshot.currentBoard)
        #expect(loaded.status == snapshot.status)
        #expect(loaded.elapsedSeconds == snapshot.elapsedSeconds)
        #expect(loaded.undoMoves == snapshot.undoMoves)
        #expect(loaded.notes == snapshot.notes)
    }

    @Test func markCompletedSetsStatus() async throws {
        let (store, _, _) = await makeStore()
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        let session = GameSession(puzzle: puzzle)
        let snapshot = await session.snapshot()
        try await store.save(snapshot, puzzleId: "p1", mode: .daily, difficulty: .easy)
        let summary = SavedGameSummary(
            recordName: SavedGameStore.recordName(for: "p1", mode: .daily),
            puzzleId: "p1",
            mode: .daily,
            difficulty: .easy,
            lastModifiedAt: Date(timeIntervalSince1970: 0),
            elapsedSeconds: 0,
            status: "inProgress",
            generatorVersion: 1
        )
        try await store.markCompleted(summary)
        let latest = try await store.latestInProgress()
        #expect(latest == nil) // none in-progress anymore
    }

    @Test func deleteAbandonedRemovesRecord() async throws {
        let (store, gateway, _) = await makeStore()
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        let session = GameSession(puzzle: puzzle)
        let snapshot = await session.snapshot()
        try await store.save(snapshot, puzzleId: "p1", mode: .practice, difficulty: .easy)
        let recordName = SavedGameStore.recordName(for: "p1", mode: .practice)
        try await store.deleteAbandoned(recordName: recordName)
        let count = await gateway.recordCount()
        #expect(count == 0)
        // loadOrCreate re-seeds a fresh record.
        let reseeded = try await store.loadOrCreate(puzzleId: "p1", mode: .practice, difficulty: .easy)
        #expect(reseeded.status == .idle)
    }

    @Test func generatorVersionPersisted() async throws {
        let (store, gateway, _) = await makeStore()
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        let session = GameSession(puzzle: puzzle)
        let snapshot = await session.snapshot()
        try await store.save(snapshot, puzzleId: "pX", mode: .daily, difficulty: .easy)

        let recordName = SavedGameStore.recordName(for: "pX", mode: .daily)
        let payload = try await gateway.fetch(recordName: recordName)
        guard case .int(let value) = payload?.fields[SavedGameStore.Field.generatorVersion] else {
            Issue.record("generatorVersion field missing")
            return
        }
        #expect(value == 1)
    }

    @Test func saveEmitsTelemetry_gameSaved() async throws {
        let (store, _, sink) = await makeStore()
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        let session = GameSession(puzzle: puzzle)
        let snapshot = await session.snapshot()
        try await store.save(snapshot, puzzleId: "p-tele", mode: .practice, difficulty: .easy)

        let received = await sink.received
        #expect(received.contains(.gameSaved(puzzleId: "p-tele")))
    }

    @Test func saveFailureEmitsTelemetry_gameSaveFailed() async throws {
        let (store, gateway, sink) = await makeStore()
        await gateway.setFailureMode(.alwaysOnSave(.quotaExceeded))
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        let session = GameSession(puzzle: puzzle)
        let snapshot = await session.snapshot()
        await #expect(throws: PersistenceError.self) {
            try await store.save(snapshot, puzzleId: "p-fail", mode: .practice, difficulty: .easy)
        }
        let received = await sink.received
        #expect(received.contains(.gameSaveFailed(puzzleId: "p-fail", reason: "quotaExceeded")))
    }

    // MARK: - #512 offline resilience

    /// When `gateway.fetch` throws (e.g. iCloud signed out / network error),
    /// `loadOrCreate` must NOT propagate the error — it must return a fresh
    /// local snapshot generated by the deterministic `puzzleLoader`.
    /// This ensures Sudoku is playable without iCloud (#512).
    @Test func loadOrCreate_fetchError_returnsFreshLocalSnapshot() async throws {
        let (store, gateway, sink) = await makeStore()
        // Inject a fetch error simulating iCloud-not-authenticated.
        await gateway.setFetchError(PersistenceError.iCloudNotSignedIn)
        // loadOrCreate must not throw; it must return the puzzle's idle snapshot.
        let snapshot = try await store.loadOrCreate(
            puzzleId: "practice-offline-easy",
            mode: .practice,
            difficulty: .easy
        )
        #expect(snapshot.status == .idle)
        #expect(snapshot.elapsedSeconds == 0)
        // Telemetry must record the swallowed fetch failure.
        let received = await sink.received
        #expect(received.contains(.gameSaveFailed(puzzleId: "practice-offline-easy", reason: "fetchFailed")))
    }

    /// DATA-LOSS REGRESSION (#512 CR): a saved in-progress game EXISTS, but the
    /// fetch fails *transiently* (network blip, not signed-out). `loadOrCreate`
    /// must (a) return a fresh playable snapshot without throwing, AND (b) NOT
    /// overwrite the existing record — because a failed fetch cannot confirm the
    /// record's absence, persisting a blank idle board here would clobber the
    /// player's real progress. The store must skip the initial save entirely on
    /// the fetch-failed path; the VM persists later on the first move.
    @Test func loadOrCreate_fetchErrorWithExistingSave_doesNotOverwrite() async throws {
        let (store, gateway, _) = await makeStore()

        // Seed a real in-progress save (digit placed, elapsed advanced).
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        let session = GameSession(puzzle: puzzle)
        try await session.start()
        try await session.placeDigit(row: 0, col: 0, digit: 1)
        let inProgress = await session.snapshot()
        try await store.save(inProgress, puzzleId: "practice-existing-easy", mode: .practice, difficulty: .easy)

        let recordName = SavedGameStore.recordName(for: "practice-existing-easy", mode: .practice)
        let before = try await gateway.fetch(recordName: recordName)
        #expect(before != nil)

        // Inject a *transient* fetch error and forget prior ops so the save
        // assertion only counts ops from the load path under test.
        await gateway.setFetchError(PersistenceError.underlying(domain: "Persistence", code: -1009, description: "network blip"))
        await gateway.resetOperations()

        // Load must not throw and must hand back a fresh playable snapshot.
        let loaded = try await store.loadOrCreate(
            puzzleId: "practice-existing-easy",
            mode: .practice,
            difficulty: .easy
        )
        #expect(loaded.status == .idle)

        // (b) NO save occurred on the fetch-failed load path → no clobber.
        let ops = await gateway.operations
        let saveOps = ops.filter {
            if case .save = $0 { return true }
            return false
        }
        #expect(saveOps.isEmpty)

        // The original record is byte-identical (clear the error to read back).
        await gateway.setFetchError(nil)
        let after = try await gateway.fetch(recordName: recordName)
        #expect(after == before)
    }
}
