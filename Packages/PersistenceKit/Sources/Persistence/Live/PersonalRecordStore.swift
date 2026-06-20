// PersonalRecordStore — CRUD for `PersonalRecord` (§How.2 + §How.2 末段).
//
// Upserts apply the «same puzzleId 不重計分» rule via the
// `completedPuzzleIds: Set<String>` field: a second completion of the
// same puzzle for the same `(mode, difficulty)` is a no-op.
//
// `recordName` is deterministic (`{mode}-{difficulty}`) so first-completion
// races collapse to a single record at the CloudKit layer.
//
// #552: `recordCompletion` uses `.ifUnchanged` optimistic concurrency with a
// bounded retry loop to prevent a stale device B from clobbering device A's
// faster best-time. `upsert` remains `.lastWriteWins` (generic facade path).

internal import Foundation
internal import SudokuEngine

internal actor PersonalRecordStore: Sendable {

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

    init(
        gateway: any PrivateCKGateway,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.gateway = gateway
        self.clock = clock
    }

    func fetch(mode: Mode, difficulty: Difficulty) async throws -> PersonalRecord {
        let recordName = Self.recordName(mode: mode, difficulty: difficulty)
        if let payload = try await gateway.fetch(recordName: recordName),
           let record = PersonalRecordMapper.record(from: payload) {
            return record
        }
        return PersonalRecord.empty(mode: mode, difficulty: difficulty, at: clock())
    }

    func upsert(_ record: PersonalRecord) async throws {
        // Generic facade path: `.lastWriteWins` (last-write-wins is correct
        // for callers that have already resolved the merge externally).
        let payload = PersonalRecordMapper.payload(from: record)
        try await gateway.save(payload, policy: .lastWriteWins)
    }

    /// High-level "record this completion" entry. Uses `.ifUnchanged`
    /// optimistic concurrency with a bounded retry loop (#552):
    ///   fetch (carries etag) → merge → save(.ifUnchanged)
    ///   on .syncConflict: re-fetch → re-merge → retry
    /// This prevents a stale device B from clobbering device A's faster
    /// best-time. Dedup: already-counted `puzzleId` → returns existing.
    @discardableResult
    func recordCompletion(
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty,
        elapsedSeconds: Int
    ) async throws -> PersonalRecord {
        let name = Self.recordName(mode: mode, difficulty: difficulty)
        let maxAttempts = 3
        for _ in 0..<maxAttempts {
            let existingPayload = try await gateway.fetch(recordName: name)
            let existing = existingPayload.flatMap(PersonalRecordMapper.record) ??
                PersonalRecord.empty(mode: mode, difficulty: difficulty, at: clock())
            guard let updated = existing.recordingCompletion(
                puzzleId: puzzleId, elapsedSeconds: elapsedSeconds, at: clock()
            ) else {
                // puzzleId already counted — dedup no-op
                return existing
            }
            var payload = PersonalRecordMapper.payload(from: updated)
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

    static func recordName(mode: Mode, difficulty: Difficulty) -> String {
        "\(mode.rawValue)-\(difficulty.rawValue)"
    }
}

// MARK: - Mapper

internal enum PersonalRecordMapper {

    static func payload(from record: PersonalRecord) -> RecordPayload {
        // M5 (issue #65): wire format encodes `.rawValue` (existing records
        // round-trip — `Mode.daily.rawValue == "daily"` etc.).
        var fields: [String: RecordValue] = [
            PersonalRecordStore.Field.mode: .string(record.mode.rawValue),
            PersonalRecordStore.Field.difficulty: .string(record.difficulty.rawValue),
            PersonalRecordStore.Field.totalTimeSeconds: .int(record.totalTimeSeconds),
            PersonalRecordStore.Field.completedCount: .int(record.completedCount),
            PersonalRecordStore.Field.lastUpdatedAt: .date(record.lastUpdatedAt),
            PersonalRecordStore.Field.completedPuzzleIds: .stringSet(Array(record.completedPuzzleIds).sorted()),
            PersonalRecordStore.Field.schemaVersion: .int(PersonalRecordStore.currentSchemaVersion)
        ]
        if let bestTime = record.bestTimeSeconds {
            fields[PersonalRecordStore.Field.bestTimeSeconds] = .int(bestTime)
        }
        return RecordPayload(
            recordType: PrivateCKConstants.personalRecordRecordType,
            recordName: record.recordName,
            fields: fields
        )
    }

    static func record(from payload: RecordPayload) -> PersonalRecord? {
        guard
            case .string(let modeRaw) = payload.fields[PersonalRecordStore.Field.mode],
            case .string(let difficultyRaw) = payload.fields[PersonalRecordStore.Field.difficulty],
            case .int(let total) = payload.fields[PersonalRecordStore.Field.totalTimeSeconds],
            case .int(let count) = payload.fields[PersonalRecordStore.Field.completedCount],
            case .date(let last) = payload.fields[PersonalRecordStore.Field.lastUpdatedAt]
        else {
            return nil
        }
        // M5 (issue #65): drop the row if wire format carries an unknown
        // raw value (forward-compat — same posture as the other guards).
        guard let mode = Mode(rawValue: modeRaw),
              let difficulty = Difficulty(rawValue: difficultyRaw) else {
            return nil
        }
        let bestTime: Int?
        if case .int(let value) = payload.fields[PersonalRecordStore.Field.bestTimeSeconds] {
            bestTime = value
        } else {
            bestTime = nil
        }
        let ids: Set<String>
        if case .stringSet(let strings) = payload.fields[PersonalRecordStore.Field.completedPuzzleIds] {
            ids = Set(strings)
        } else {
            ids = []
        }
        return PersonalRecord(
            recordName: payload.recordName,
            mode: mode,
            difficulty: difficulty,
            bestTimeSeconds: bestTime,
            totalTimeSeconds: total,
            completedCount: count,
            lastUpdatedAt: last,
            completedPuzzleIds: ids
        )
    }
}
