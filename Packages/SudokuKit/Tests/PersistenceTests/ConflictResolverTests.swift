// ConflictResolverTests — Phase 5.6: per-field LWW (§How.6.7) +
// 2-retry budget.

import Foundation
import Testing
@testable import Persistence

@Suite("Persistence — conflict resolver")
struct ConflictResolverTests {

    private func savedGame(
        board: String,
        notes: Data,
        undo: Data,
        elapsed: Int,
        status: String,
        at time: TimeInterval
    ) -> ConflictResolver.SavedGameSnapshot {
        ConflictResolver.SavedGameSnapshot(
            boardState: board,
            notesState: notes,
            undoStack: undo,
            elapsedSeconds: elapsed,
            status: status,
            lastModifiedAt: Date(timeIntervalSince1970: time)
        )
    }

    @Test func boardNotesUndoSwitchedAsGroup() {
        let local = savedGame(
            board: "L", notes: Data([1]), undo: Data([1]),
            elapsed: 50, status: "inProgress", at: 100
        )
        let server = savedGame(
            board: "S", notes: Data([2]), undo: Data([2]),
            elapsed: 50, status: "inProgress", at: 200
        )
        let resolved = ConflictResolver.resolve(local: local, server: server)
        // Server is newer → all three group fields come from server.
        #expect(resolved.boardState == "S")
        #expect(resolved.notesState == Data([2]))
        #expect(resolved.undoStack == Data([2]))
    }

    @Test func elapsedSecondsTakesMax() {
        let local = savedGame(
            board: "L", notes: Data(), undo: Data(),
            elapsed: 30, status: "inProgress", at: 100
        )
        let server = savedGame(
            board: "S", notes: Data(), undo: Data(),
            elapsed: 75, status: "inProgress", at: 50
        )
        let resolved = ConflictResolver.resolve(local: local, server: server)
        #expect(resolved.elapsedSeconds == 75)
    }

    @Test func statusCompletedWinsOverInProgress() {
        let localCompleted = savedGame(
            board: "L", notes: Data(), undo: Data(),
            elapsed: 60, status: "completed", at: 50
        )
        let serverInProgress = savedGame(
            board: "S", notes: Data(), undo: Data(),
            elapsed: 60, status: "inProgress", at: 200
        )
        let resolved = ConflictResolver.resolve(local: localCompleted, server: serverInProgress)
        #expect(resolved.status == "completed")
    }

    @Test func personalRecordBestTimeTakesMin() {
        let now = Date(timeIntervalSince1970: 1_000)
        let local = PersonalRecord(
            recordName: "daily-easy", mode: "daily", difficulty: "easy",
            bestTimeSeconds: 120, totalTimeSeconds: 300, completedCount: 2,
            lastUpdatedAt: now, completedPuzzleIds: ["a", "b"]
        )
        let server = PersonalRecord(
            recordName: "daily-easy", mode: "daily", difficulty: "easy",
            bestTimeSeconds: 90, totalTimeSeconds: 200, completedCount: 1,
            lastUpdatedAt: now, completedPuzzleIds: ["b", "c"]
        )
        let resolved = ConflictResolver.resolve(local: local, server: server)
        #expect(resolved.bestTimeSeconds == 90)
    }

    @Test func personalRecordCountsTakeMax() {
        let now = Date(timeIntervalSince1970: 1_000)
        let local = PersonalRecord(
            recordName: "daily-easy", mode: "daily", difficulty: "easy",
            bestTimeSeconds: 120, totalTimeSeconds: 300, completedCount: 2,
            lastUpdatedAt: now, completedPuzzleIds: ["a"]
        )
        let server = PersonalRecord(
            recordName: "daily-easy", mode: "daily", difficulty: "easy",
            bestTimeSeconds: 120, totalTimeSeconds: 500, completedCount: 4,
            lastUpdatedAt: now, completedPuzzleIds: ["b"]
        )
        let resolved = ConflictResolver.resolve(local: local, server: server)
        #expect(resolved.totalTimeSeconds == 500)
        #expect(resolved.completedCount == 4)
    }

    @Test func personalRecordCompletedPuzzleIdsTakeUnion() {
        let now = Date(timeIntervalSince1970: 1_000)
        let local = PersonalRecord(
            recordName: "daily-easy", mode: "daily", difficulty: "easy",
            bestTimeSeconds: 120, totalTimeSeconds: 300, completedCount: 2,
            lastUpdatedAt: now, completedPuzzleIds: ["a", "b"]
        )
        let server = PersonalRecord(
            recordName: "daily-easy", mode: "daily", difficulty: "easy",
            bestTimeSeconds: 120, totalTimeSeconds: 300, completedCount: 2,
            lastUpdatedAt: now, completedPuzzleIds: ["b", "c"]
        )
        let resolved = ConflictResolver.resolve(local: local, server: server)
        #expect(resolved.completedPuzzleIds == ["a", "b", "c"])
    }

    @Test func threeConflictsThrowSyncConflict() async throws {
        // Always-conflict harness → exhausts the 2-retry budget on the 3rd.
        await #expect(throws: PersistenceError.self) {
            _ = try await RetryHarness.run(recordName: "rec-1") { _ in
                .conflict
            } as Void
        }
    }

    @Test func twoConflictsThenSuccessReturnsValue() async throws {
        let counter = AttemptCounter()
        let value: String = try await RetryHarness.run(recordName: "rec-1") { attempt in
            await counter.record(attempt)
            if attempt < 2 { return .conflict }
            return .success("done")
        }
        #expect(value == "done")
        let observed = await counter.count
        #expect(observed == 3) // attempts 0, 1, 2
    }
}

private actor AttemptCounter {
    private(set) var count: Int = 0
    func record(_ attempt: Int) { count += 1 }
}
