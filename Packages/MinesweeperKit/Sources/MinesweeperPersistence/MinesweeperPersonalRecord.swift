// MinesweeperPersonalRecord — per (modeRaw × difficulty) personal best.
//
// Structural mirror of Sudoku's `PersonalRecord`
// (Packages/PersistenceKit/Sources/Persistence/PersonalRecord.swift), with
// MS-native types: `modeRaw` stays a `String` ("daily" / "practice") rather
// than a typed enum, mirroring `MinesweeperSavedGameStore`'s existing
// `modeRaw` precedent — `GameMode` lives in `MinesweeperUI`, which depends ON
// this target, not the reverse.
//
// #699 (owner decision, 2026-07-05): MS-specific data type, deliberately NOT
// wired through the shared `TelemetryEvent` / `PersonalRecordSink` /
// `makeCompletionSinks` pipeline — same precedent as `MinesweeperSavedGameStore`
// and the Game Center best-time submit in
// `MinesweeperGameViewModel.submitDailyTimeIfWon()`.
//
// `recordName` is deterministic (`"\(modeRaw)-\(difficulty.rawValue)"`) so
// concurrent first-completion races on two devices collapse to a single
// record (mirrors Sudoku's `PersonalRecord`).

public import Foundation
public import MinesweeperEngine

public struct MinesweeperPersonalRecord: Sendable, Equatable, Hashable, Codable {
    /// Deterministic key: `"\(modeRaw)-\(difficulty.rawValue)"`, e.g. `"daily-beginner"`.
    public let recordName: String
    public let modeRaw: String
    public let difficulty: Difficulty
    /// `nil` until the first completion lands.
    public let bestTimeSeconds: Int?
    public let totalTimeSeconds: Int
    public let completedCount: Int
    public let lastUpdatedAt: Date
    /// puzzleIds (board recordNames) already counted toward this record —
    /// drives "the same board does not double-count" (mirrors Sudoku's
    /// «同 puzzleId 不重計分» rule).
    public let completedPuzzleIds: Set<String>

    public init(
        recordName: String,
        modeRaw: String,
        difficulty: Difficulty,
        bestTimeSeconds: Int?,
        totalTimeSeconds: Int,
        completedCount: Int,
        lastUpdatedAt: Date,
        completedPuzzleIds: Set<String>
    ) {
        self.recordName = recordName
        self.modeRaw = modeRaw
        self.difficulty = difficulty
        self.bestTimeSeconds = bestTimeSeconds
        self.totalTimeSeconds = totalTimeSeconds
        self.completedCount = completedCount
        self.lastUpdatedAt = lastUpdatedAt
        self.completedPuzzleIds = completedPuzzleIds
    }

    /// Empty initial record for a `(modeRaw, difficulty)` pair. Used by the
    /// store when no record yet exists.
    public static func empty(modeRaw: String, difficulty: Difficulty, at date: Date) -> MinesweeperPersonalRecord {
        MinesweeperPersonalRecord(
            recordName: "\(modeRaw)-\(difficulty.rawValue)",
            modeRaw: modeRaw,
            difficulty: difficulty,
            bestTimeSeconds: nil,
            totalTimeSeconds: 0,
            completedCount: 0,
            lastUpdatedAt: date,
            completedPuzzleIds: []
        )
    }

    /// Returns the record updated for one completion, or `nil` if `puzzleId`
    /// was already counted (dedup). Pure — no IO.
    public func recordingCompletion(puzzleId: String, elapsedSeconds: Int, at date: Date) -> MinesweeperPersonalRecord? {
        guard !completedPuzzleIds.contains(puzzleId) else { return nil }
        var ids = completedPuzzleIds
        ids.insert(puzzleId)
        let newBest = bestTimeSeconds.map { min($0, elapsedSeconds) } ?? elapsedSeconds
        return MinesweeperPersonalRecord(
            recordName: recordName, modeRaw: modeRaw, difficulty: difficulty,
            bestTimeSeconds: newBest,
            totalTimeSeconds: totalTimeSeconds + elapsedSeconds,
            completedCount: completedCount + 1,
            lastUpdatedAt: date,
            completedPuzzleIds: ids
        )
    }
}
