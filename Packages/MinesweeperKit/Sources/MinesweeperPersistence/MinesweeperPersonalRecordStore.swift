// MinesweeperPersonalRecordStore — CRUD for `MinesweeperPersonalRecord`.
//
// Structural + concurrency mirror of Sudoku's `PersonalRecordStore`
// (Packages/PersistenceKit/Sources/Persistence/Live/PersonalRecordStore.swift):
// same `.ifUnchanged` optimistic-concurrency retry loop (bounded 3 attempts)
// so a stale device doesn't clobber a faster best-time (mirrors Sudoku's #552).
//
// Reuses the shared `PrivateCKConstants.personalRecordRecordType`
// ("PersonalRecord") record-type NAME — safe because MS and Sudoku each own a
// separate CKContainer (see `MinesweeperSavedGameStore`'s doc comment for the
// identical precedent with `"SavedGame"`).
//
// #699 (owner decision, 2026-07-05): MS-specific store, constructed directly
// in `MinesweeperAppComposition.live()` and called from
// `MinesweeperGameViewModel.submitDailyTimeIfWon()` — deliberately NOT wired
// through the shared `TelemetryEvent` / `PersonalRecordSink` /
// `makeCompletionSinks` pipeline (generalizing that pipeline to a second
// game's types is left to #479).

public import Foundation
public import MinesweeperEngine
public import Persistence

public actor MinesweeperPersonalRecordStore: Sendable {

    enum Field {
        static let mode = "mode"
        static let difficulty = "difficulty"
        static let bestTimeSeconds = "bestTimeSeconds"
        static let totalTimeSeconds = "totalTimeSeconds"
        static let completedCount = "completedCount"
        static let lastUpdatedAt = "lastUpdatedAt"
        static let completedPuzzleIds = "completedPuzzleIds"
        static let schemaVersion = "schemaVersion"
    }

    static let currentSchemaVersion = 1

    private let gateway: any PrivateCKGateway
    private let clock: @Sendable () -> Date

    public init(
        gateway: any PrivateCKGateway,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.gateway = gateway
        self.clock = clock
    }

    public func fetch(modeRaw: String, difficulty: Difficulty) async throws -> MinesweeperPersonalRecord {
        let recordName = Self.recordName(modeRaw: modeRaw, difficulty: difficulty)
        if let payload = try await gateway.fetch(recordName: recordName),
           let record = MinesweeperPersonalRecordMapper.record(from: payload) {
            return record
        }
        return MinesweeperPersonalRecord.empty(modeRaw: modeRaw, difficulty: difficulty, at: clock())
    }

    /// High-level "record this completion" entry. Uses `.ifUnchanged`
    /// optimistic concurrency with a bounded retry loop:
    ///   fetch (carries etag) → merge → save(.ifUnchanged)
    ///   on .syncConflict: re-fetch → re-merge → retry
    /// This prevents a stale device B from clobbering device A's faster
    /// best-time. Dedup: already-counted `puzzleId` → returns existing.
    @discardableResult
    public func recordCompletion(
        puzzleId: String,
        modeRaw: String,
        difficulty: Difficulty,
        elapsedSeconds: Int
    ) async throws -> MinesweeperPersonalRecord {
        let name = Self.recordName(modeRaw: modeRaw, difficulty: difficulty)
        let maxAttempts = 3
        for _ in 0..<maxAttempts {
            let existingPayload = try await gateway.fetch(recordName: name)
            let existing = existingPayload.flatMap(MinesweeperPersonalRecordMapper.record) ??
                MinesweeperPersonalRecord.empty(modeRaw: modeRaw, difficulty: difficulty, at: clock())
            guard let updated = existing.recordingCompletion(
                puzzleId: puzzleId, elapsedSeconds: elapsedSeconds, at: clock()
            ) else {
                // puzzleId already counted — dedup no-op
                return existing
            }
            var payload = MinesweeperPersonalRecordMapper.payload(from: updated)
            payload.encodedSystemFields = existingPayload?.encodedSystemFields
            do {
                try await gateway.save(payload, policy: .ifUnchanged)
                return updated
            } catch PersistenceError.syncConflict {
                // Server record changed since our fetch — re-fetch and retry
                continue
            }
        }
        throw PersistenceError.syncConflict(recordName: name)
    }

    static func recordName(modeRaw: String, difficulty: Difficulty) -> String {
        "\(modeRaw)-\(difficulty.rawValue)"
    }
}

// MARK: - Mapper

enum MinesweeperPersonalRecordMapper {

    static func payload(from record: MinesweeperPersonalRecord) -> RecordPayload {
        var fields: [String: RecordValue] = [
            MinesweeperPersonalRecordStore.Field.mode: .string(record.modeRaw),
            MinesweeperPersonalRecordStore.Field.difficulty: .string(record.difficulty.rawValue),
            MinesweeperPersonalRecordStore.Field.totalTimeSeconds: .int(record.totalTimeSeconds),
            MinesweeperPersonalRecordStore.Field.completedCount: .int(record.completedCount),
            MinesweeperPersonalRecordStore.Field.lastUpdatedAt: .date(record.lastUpdatedAt),
            MinesweeperPersonalRecordStore.Field.completedPuzzleIds: .stringSet(Array(record.completedPuzzleIds).sorted()),
            MinesweeperPersonalRecordStore.Field.schemaVersion: .int(MinesweeperPersonalRecordStore.currentSchemaVersion)
        ]
        if let bestTime = record.bestTimeSeconds {
            fields[MinesweeperPersonalRecordStore.Field.bestTimeSeconds] = .int(bestTime)
        }
        return RecordPayload(
            recordType: PrivateCKConstants.personalRecordRecordType,
            recordName: record.recordName,
            fields: fields
        )
    }

    static func record(from payload: RecordPayload) -> MinesweeperPersonalRecord? {
        guard
            case .string(let modeRaw) = payload.fields[MinesweeperPersonalRecordStore.Field.mode],
            case .string(let difficultyRaw) = payload.fields[MinesweeperPersonalRecordStore.Field.difficulty],
            case .int(let total) = payload.fields[MinesweeperPersonalRecordStore.Field.totalTimeSeconds],
            case .int(let count) = payload.fields[MinesweeperPersonalRecordStore.Field.completedCount],
            case .date(let last) = payload.fields[MinesweeperPersonalRecordStore.Field.lastUpdatedAt]
        else {
            return nil
        }
        // Forward-compat: drop the row if the wire format carries an unknown
        // difficulty raw value (mirrors Sudoku's PersonalRecordMapper guard).
        guard let difficulty = Difficulty(rawValue: difficultyRaw) else {
            return nil
        }
        let bestTime: Int?
        if case .int(let value) = payload.fields[MinesweeperPersonalRecordStore.Field.bestTimeSeconds] {
            bestTime = value
        } else {
            bestTime = nil
        }
        let ids: Set<String>
        if case .stringSet(let strings) = payload.fields[MinesweeperPersonalRecordStore.Field.completedPuzzleIds] {
            ids = Set(strings)
        } else {
            ids = []
        }
        return MinesweeperPersonalRecord(
            recordName: payload.recordName,
            modeRaw: modeRaw,
            difficulty: difficulty,
            bestTimeSeconds: bestTime,
            totalTimeSeconds: total,
            completedCount: count,
            lastUpdatedAt: last,
            completedPuzzleIds: ids
        )
    }
}
