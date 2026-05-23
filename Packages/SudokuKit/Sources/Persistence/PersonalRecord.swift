// PersonalRecord — per (mode × difficulty) personal best.
//
// Per docs/v1/design.md §How.2 (Private DB schema, max 6 records / player) +
// §How.2 末段 («同 puzzleId 不重計分») — `completedPuzzleIds` provides the
// dedup key for "the same puzzle does not double-count".
//
// `recordName` is deterministic (`{mode}-{difficulty}`) so concurrent
// first-completion races on two devices collapse to a single record via
// `.ifServerRecordUnchanged` + retry (§How.6.7).

public import Foundation

public struct PersonalRecord: Sendable, Equatable, Hashable, Codable {
    /// Deterministic key: `"\(mode)-\(difficulty)"`, e.g. `"daily-easy"`.
    public let recordName: String
    public let mode: String
    public let difficulty: String
    /// `nil` until the first completion lands.
    public let bestTimeSeconds: Int?
    public let totalTimeSeconds: Int
    public let completedCount: Int
    public let lastUpdatedAt: Date
    /// puzzleIds that have already been counted toward this record. Drives
    /// the "same puzzleId no rescore" rule from §How.2.
    public let completedPuzzleIds: Set<String>

    public init(
        recordName: String,
        mode: String,
        difficulty: String,
        bestTimeSeconds: Int?,
        totalTimeSeconds: Int,
        completedCount: Int,
        lastUpdatedAt: Date,
        completedPuzzleIds: Set<String>
    ) {
        self.recordName = recordName
        self.mode = mode
        self.difficulty = difficulty
        self.bestTimeSeconds = bestTimeSeconds
        self.totalTimeSeconds = totalTimeSeconds
        self.completedCount = completedCount
        self.lastUpdatedAt = lastUpdatedAt
        self.completedPuzzleIds = completedPuzzleIds
    }

    /// Empty initial record for a `(mode, difficulty)` pair. Used by the
    /// store when no record yet exists.
    public static func empty(mode: String, difficulty: String, at date: Date) -> PersonalRecord {
        PersonalRecord(
            recordName: "\(mode)-\(difficulty)",
            mode: mode,
            difficulty: difficulty,
            bestTimeSeconds: nil,
            totalTimeSeconds: 0,
            completedCount: 0,
            lastUpdatedAt: date,
            completedPuzzleIds: []
        )
    }
}
