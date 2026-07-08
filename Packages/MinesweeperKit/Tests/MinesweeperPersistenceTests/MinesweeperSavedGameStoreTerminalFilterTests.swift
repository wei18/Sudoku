// MinesweeperSavedGameStore — terminal-record resume filter (#700 CR).
// Split from MinesweeperSavedGameStoreTests.swift purely for the 400-line
// file_length ceiling; same fixtures and philosophy.

import Foundation
import Testing
import MinesweeperEngine
import MinesweeperGameState
import Persistence
import PersistenceTesting
@testable import MinesweeperPersistence

@Suite("MinesweeperSavedGameStore — terminal records are not resumable (#700 CR)")
struct MinesweeperSavedGameStoreTerminalFilterTests {

    private static let fixedDate = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeStore(_ gateway: FakePrivateCKGateway) -> MinesweeperSavedGameStore {
        MinesweeperSavedGameStore(gateway: gateway, clock: { Self.fixedDate })
    }

    private func midPlaySnapshot() async throws -> MinesweeperSessionSnapshot {
        let session = MinesweeperSession(difficulty: .beginner, seed: 42)
        _ = try await session.reveal(row: 4, col: 4)
        return await session.snapshot()
    }

    /// #700 CR (MAJOR 1): a terminal record must not be resumable through
    /// `loadInProgress` — handing a `.won` session to a fresh ViewModel
    /// (whose per-instance latches are unset) would re-run win side effects
    /// and inflate the non-idempotent achievement win tally. Mirrors
    /// `latestInProgress()`'s status filter.
    @Test("loadInProgress returns nil for terminal records (completed / failed), still loads in-progress")
    func loadInProgressReturnsNilForTerminalRecords() async throws {
        let gateway = FakePrivateCKGateway()
        let store = makeStore(gateway)
        let base = try await midPlaySnapshot()

        func terminal(_ status: MinesweeperSessionStatus) -> MinesweeperSessionSnapshot {
            MinesweeperSessionSnapshot(
                difficulty: base.difficulty, seed: base.seed, cells: base.cells,
                status: status, elapsedSeconds: base.elapsedSeconds,
                mineCount: base.mineCount, flagCount: base.flagCount
            )
        }

        try await store.save(terminal(.won), modeRaw: "daily", recordName: "ms-won")
        #expect(try await store.loadInProgress(recordName: "ms-won") == nil)

        try await store.save(terminal(.lost), modeRaw: "daily", recordName: "ms-lost")
        #expect(try await store.loadInProgress(recordName: "ms-lost") == nil)

        // A genuinely in-progress save still loads.
        try await store.save(base, modeRaw: "daily", recordName: "ms-live")
        #expect(try await store.loadInProgress(recordName: "ms-live") != nil)
    }
}
