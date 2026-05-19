// ConflictResolver — pure per-field LWW resolution per design.md §How.6.7.
//
// SavedGame:
//   - boardState / notesState / undoStack: switch as a GROUP based on
//     `lastModifiedAt` (newer wins).
//   - elapsedSeconds: `max(local, server)`.
//   - status: "completed" beats "inProgress"; otherwise newer `lastModifiedAt`.
//   - lastModifiedAt: the newer of the two.
//
// PersonalRecord:
//   - bestTimeSeconds: `min(local, server)` (nil treated as +∞).
//   - completedCount / totalTimeSeconds: `max(local, server)`.
//   - completedPuzzleIds: union.
//   - lastUpdatedAt: newer.
//
// Save loop budget: at most 2 conflict retries; 3rd → `PersistenceError
// .syncConflict`.

internal import Foundation

internal enum ConflictResolver {

    static let maxRetries = 2

    // MARK: - SavedGame

    /// Snapshot-shaped record carrying just the conflict-relevant fields.
    /// We do NOT round-trip through `RecordPayload` here so the resolver
    /// stays a pure function over the schema-relevant subset.
    struct SavedGameSnapshot: Sendable, Equatable {
        let boardState: String
        let notesState: Data
        let undoStack: Data
        let elapsedSeconds: Int
        let status: String
        let lastModifiedAt: Date
    }

    static func resolve(local: SavedGameSnapshot, server: SavedGameSnapshot) -> SavedGameSnapshot {
        // boardState / notesState / undoStack — pick GROUP from newer.
        let newer: SavedGameSnapshot
        if local.lastModifiedAt >= server.lastModifiedAt {
            newer = local
        } else {
            newer = server
        }
        let resolvedStatus: String
        if local.status == "completed" || server.status == "completed" {
            resolvedStatus = "completed"
        } else {
            resolvedStatus = newer.status
        }
        return SavedGameSnapshot(
            boardState: newer.boardState,
            notesState: newer.notesState,
            undoStack: newer.undoStack,
            elapsedSeconds: max(local.elapsedSeconds, server.elapsedSeconds),
            status: resolvedStatus,
            lastModifiedAt: max(local.lastModifiedAt, server.lastModifiedAt)
        )
    }

    // MARK: - PersonalRecord

    static func resolve(local: PersonalRecord, server: PersonalRecord) -> PersonalRecord {
        let bestTime: Int?
        switch (local.bestTimeSeconds, server.bestTimeSeconds) {
        case let (someLocal?, someServer?): bestTime = min(someLocal, someServer)
        case let (someLocal?, nil): bestTime = someLocal
        case let (nil, someServer?): bestTime = someServer
        case (nil, nil): bestTime = nil
        }
        return PersonalRecord(
            recordName: local.recordName,
            mode: local.mode,
            difficulty: local.difficulty,
            bestTimeSeconds: bestTime,
            totalTimeSeconds: max(local.totalTimeSeconds, server.totalTimeSeconds),
            completedCount: max(local.completedCount, server.completedCount),
            lastUpdatedAt: max(local.lastUpdatedAt, server.lastUpdatedAt),
            completedPuzzleIds: local.completedPuzzleIds.union(server.completedPuzzleIds)
        )
    }
}

// MARK: - Retry harness

/// Generic save-with-retry harness used by the live store layer. The
/// `attempt` closure receives the latest known server state (nil on the
/// first try) and returns the merged record to persist. If the closure
/// throws a `serverRecordChanged`-equivalent signal, the harness fetches
/// the new server state and re-invokes `attempt`. After `ConflictResolver
/// .maxRetries` failed attempts a `PersistenceError.syncConflict` is
/// thrown.
internal struct RetryHarness {

    /// Loop signal — kept internal so test harnesses can model it without
    /// pulling in CloudKit.
    enum LoopOutcome<T: Sendable>: Sendable {
        case success(T)
        case conflict
    }

    static func run<T: Sendable>(
        recordName: String,
        body: @Sendable (Int) async throws -> LoopOutcome<T>
    ) async throws -> T {
        var attempts = 0
        while attempts <= ConflictResolver.maxRetries {
            let outcome = try await body(attempts)
            switch outcome {
            case .success(let value):
                return value
            case .conflict:
                attempts += 1
                continue
            }
        }
        throw PersistenceError.syncConflict(recordName: recordName)
    }
}
