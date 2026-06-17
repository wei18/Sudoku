// MistakeCountPersistenceTests — SDD-003 Epic 3 (AC-3.4).
//
// Verifies that `mistakeCount` survives the full persistence round-trip:
// SavedGameMapper.payload → RecordPayload → SavedGameMapper.snapshot.
// Also verifies backward compatibility: a RecordPayload without the field
// decodes with mistakeCount == 0.

import Foundation
import Testing
import SudokuGameState
import SudokuEngine
import Telemetry
import TelemetryTesting
import PersistenceTesting
@testable import Persistence

@Suite("Persistence — mistakeCount round-trip (#SDD-003 Epic 3)")
struct MistakeCountPersistenceTests {

    private func makeSnapshot(mistakeCount: Int) -> GameSessionSnapshot {
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        return GameSessionSnapshot(
            puzzle: puzzle,
            currentBoard: puzzle.clues,
            status: .playing,
            elapsedSeconds: 42,
            undoMoves: [],
            redoMoves: [],
            notes: NotesGrid(),
            startedAt: nil,
            mistakeCount: mistakeCount
        )
    }

    @Test("mistakeCount survives mapper payload → snapshot round-trip")
    func mistakeCountRoundTripsViaMapper() throws {
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        let snapshot = makeSnapshot(mistakeCount: 5)

        let payload = SavedGameMapper.payload(
            from: snapshot,
            recordName: "test-record",
            puzzleId: "practice-ABC-easy",
            mode: .practice,
            difficulty: .easy,
            lastModifiedAt: Date(),
            schemaVersion: 1
        )

        let restored = try SavedGameMapper.snapshot(from: payload, puzzle: puzzle)
        #expect(restored.mistakeCount == 5)
    }

    @Test("SavedGameStore save → loadOrCreate round-trips mistakeCount")
    func storeRoundTripsMistakeCount() async throws {
        let gateway = FakePrivateCKGateway()
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        let store = SavedGameStore(
            gateway: gateway,
            telemetry: Telemetry(sinks: [RecordingSink()]),
            puzzleLoader: { _ in puzzle }
        )

        // Build a snapshot with 3 mistakes.
        let snapshot = makeSnapshot(mistakeCount: 3)
        try await store.save(
            snapshot,
            puzzleId: "practice-ABC-easy",
            mode: .practice,
            difficulty: .easy
        )

        let loaded = try await store.loadOrCreate(
            puzzleId: "practice-ABC-easy",
            mode: .practice,
            difficulty: .easy
        )
        #expect(loaded.mistakeCount == 3)
    }

    @Test("older records without mistakeCount field decode as zero")
    func missingFieldDefaultsToZero() throws {
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        // Build a payload that intentionally omits the mistakeCount field,
        // simulating a record written before the field was introduced.
        let snapshot = makeSnapshot(mistakeCount: 0)
        var payload = SavedGameMapper.payload(
            from: snapshot,
            recordName: "old-record",
            puzzleId: "practice-ABC-easy",
            mode: .practice,
            difficulty: .easy,
            lastModifiedAt: Date(),
            schemaVersion: 1
        )
        // Remove the field to simulate an older record.
        payload.fields.removeValue(forKey: SavedGameStore.Field.mistakeCount)

        let restored = try SavedGameMapper.snapshot(from: payload, puzzle: puzzle)
        #expect(restored.mistakeCount == 0, "absent field must default to 0")
    }
}
