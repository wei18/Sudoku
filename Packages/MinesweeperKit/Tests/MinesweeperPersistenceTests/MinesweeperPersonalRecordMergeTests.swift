// MinesweeperPersonalRecordMergeTests — pure method `recordingCompletion` (#699).
// Structural mirror of PersistenceKit's `PersonalRecordMergeTests`.

import Foundation
import Testing
import MinesweeperEngine
@testable import MinesweeperPersistence

@Suite("MinesweeperPersonalRecord — recordingCompletion (pure)")
struct MinesweeperPersonalRecordMergeTests {

    private let fixedDate = Date(timeIntervalSince1970: 2_000)

    private func emptyRecord(modeRaw: String = "daily", difficulty: Difficulty = .beginner) -> MinesweeperPersonalRecord {
        MinesweeperPersonalRecord.empty(modeRaw: modeRaw, difficulty: difficulty, at: Date(timeIntervalSince1970: 0))
    }

    @Test func firstCompletionSetCountBestTotal() throws {
        let record = emptyRecord()
        let updated = try #require(record.recordingCompletion(puzzleId: "p1", elapsedSeconds: 120, at: fixedDate))
        #expect(updated.completedCount == 1)
        #expect(updated.bestTimeSeconds == 120)
        #expect(updated.totalTimeSeconds == 120)
        #expect(updated.completedPuzzleIds == ["p1"])
        #expect(updated.lastUpdatedAt == fixedDate)
    }

    @Test func secondDifferentPuzzleKeepsBestAndAccumulates() throws {
        let record = emptyRecord()
        let after1 = try #require(record.recordingCompletion(puzzleId: "p1", elapsedSeconds: 100, at: fixedDate))
        let after2Date = Date(timeIntervalSince1970: 3_000)
        let updated = try #require(after1.recordingCompletion(puzzleId: "p2", elapsedSeconds: 200, at: after2Date))
        #expect(updated.completedCount == 2)
        #expect(updated.bestTimeSeconds == 100)   // min(100, 200) = 100
        #expect(updated.totalTimeSeconds == 300)  // 100 + 200
        #expect(updated.completedPuzzleIds == ["p1", "p2"])
    }

    @Test func samePuzzleIdReturnsNil() throws {
        let record = emptyRecord()
        let after1 = try #require(record.recordingCompletion(puzzleId: "p1", elapsedSeconds: 100, at: fixedDate))
        let duplicate = after1.recordingCompletion(puzzleId: "p1", elapsedSeconds: 90, at: fixedDate)
        #expect(duplicate == nil)
    }
}
