// SaveIdentityRoutingTests — Wave-2 BLOCKER B2 regression.
//
// Pre-fix bug: `PersistenceProtocol.save(_ snapshot:)` (now removed)
// routed through `SavedGameStore.save(_:)` which used
// `snapshot.puzzle.seed.description` + hardcoded mode "practice" as the
// record identity. `loadOrCreate(puzzleId:mode:difficulty:)` used the
// real puzzleId. Live writes landed on a DIFFERENT record name from
// the read — orphan records on every save.
//
// Post-fix: the protocol takes `puzzleId / mode / difficulty` alongside
// the snapshot, so save and loadOrCreate hit the SAME record name.
//
// Per impl-notes meetings/2026-05-20_wave-2-blocker-fixes.impl-notes.md §B2.

import Foundation
import GameState
import SudokuEngine
import Telemetry
import Testing
import SudokuKitTesting
import TelemetryTesting
@testable import Persistence

@Suite("Persistence — save identity routing (B2)")
struct SaveIdentityRoutingTests {

    @Test("LivePersistence.save writes to the SAME record name as loadOrCreate")
    func saveAndLoadOrCreateHitSameRecord() async throws {
        let gateway = FakePrivateCKGateway()
        let sink = RecordingSink()
        let telemetry = Telemetry(sinks: [sink])
        let puzzle = PuzzleFixtures.latinSquarePuzzle()

        let store = SavedGameStore(
            gateway: gateway,
            telemetry: telemetry,
            puzzleLoader: { _ in puzzle }
        )

        let puzzleId = "2026-05-20-easy"
        let mode: Mode = .daily
        let difficulty: Difficulty = .easy

        // 1) loadOrCreate seeds a fresh record under the QUALIFIED identity.
        _ = try await store.loadOrCreate(
            puzzleId: puzzleId, mode: mode, difficulty: difficulty
        )
        let recordNameAfterLoad = SavedGameStore.recordName(for: puzzleId, mode: mode)
        let recordAfterLoad = try await gateway.fetch(recordName: recordNameAfterLoad)
        #expect(recordAfterLoad != nil, "loadOrCreate must seed under qualified record name")
        let initialCount = await gateway.recordCount()
        #expect(initialCount == 1)

        // 2) Build a non-trivial snapshot and save it under the SAME identity.
        // The fixture has 1 missing cell at (0,0) with solution=1. Place an
        // INCORRECT digit so the board doesn't auto-complete (we want
        // status == .playing in the snapshot).
        let session = GameSession(puzzle: puzzle)
        try await session.start()
        try await session.placeDigit(row: 0, col: 0, digit: 5)
        let snapshot = await session.snapshot()

        try await store.save(
            snapshot, puzzleId: puzzleId, mode: mode, difficulty: difficulty
        )

        // 3) The gateway must still hold EXACTLY ONE record under the same
        //    name. Pre-fix, the seed-fallback path would have written to a
        //    "practice-<seed>" name → record count would become 2.
        let countAfterSave = await gateway.recordCount()
        #expect(countAfterSave == 1, "save must not create an orphan record")
        let recordAfterSave = try await gateway.fetch(recordName: recordNameAfterLoad)
        #expect(recordAfterSave != nil, "the record under the qualified name still exists")
    }

    @Test("GameViewModel-shape save: same identity round-trips through loadOrCreate")
    func roundtripUnderQualifiedIdentity() async throws {
        let gateway = FakePrivateCKGateway()
        let sink = RecordingSink()
        let telemetry = Telemetry(sinks: [sink])
        let puzzle = PuzzleFixtures.latinSquarePuzzle()
        let store = SavedGameStore(
            gateway: gateway,
            telemetry: telemetry,
            puzzleLoader: { _ in puzzle }
        )

        let puzzleId = "practice-AB-medium"
        let mode: Mode = .practice
        let difficulty: Difficulty = .medium

        // Only (0,0) is mutable on this fixture (the one missing cell).
        // Place an INCORRECT digit so we don't auto-complete.
        let session = GameSession(puzzle: puzzle)
        try await session.start()
        try await session.placeDigit(row: 0, col: 0, digit: 5)
        let snapshot = await session.snapshot()

        try await store.save(
            snapshot, puzzleId: puzzleId, mode: mode, difficulty: difficulty
        )
        let loaded = try await store.loadOrCreate(
            puzzleId: puzzleId, mode: mode, difficulty: difficulty
        )
        #expect(loaded.currentBoard == snapshot.currentBoard)
        #expect(loaded.undoMoves == snapshot.undoMoves)
    }
}
