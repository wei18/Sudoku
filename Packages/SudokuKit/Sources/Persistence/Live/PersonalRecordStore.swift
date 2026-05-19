// PersonalRecordStore — CRUD for `PersonalRecord` (§How.2 + §How.2 末段).
//
// Upserts apply the «same puzzleId 不重計分» rule via the
// `completedPuzzleIds: Set<String>` field: a second completion of the
// same puzzle for the same `(mode, difficulty)` is a no-op.
//
// `recordName` is deterministic (`{mode}-{difficulty}`) so first-completion
// races collapse to a single record at the CloudKit layer (Phase 5.6 adds
// the LWW retry loop on conflict).

internal import Foundation

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

    func fetch(mode: String, difficulty: String) async throws -> PersonalRecord {
        let recordName = Self.recordName(mode: mode, difficulty: difficulty)
        if let payload = try await gateway.fetch(recordName: recordName),
           let record = PersonalRecordMapper.record(from: payload) {
            return record
        }
        return PersonalRecord.empty(mode: mode, difficulty: difficulty, at: clock())
    }

    func upsert(_ record: PersonalRecord) async throws {
        let payload = PersonalRecordMapper.payload(from: record)
        try await gateway.save(payload)
    }

    /// High-level "record this completion" entry. Encodes the dedup rule:
    /// already-counted `puzzleId` → no-op.
    @discardableResult
    func recordCompletion(
        puzzleId: String,
        mode: String,
        difficulty: String,
        elapsedSeconds: Int
    ) async throws -> PersonalRecord {
        let existing = try await fetch(mode: mode, difficulty: difficulty)
        if existing.completedPuzzleIds.contains(puzzleId) {
            return existing
        }
        var ids = existing.completedPuzzleIds
        ids.insert(puzzleId)
        let bestTime: Int
        if let current = existing.bestTimeSeconds {
            bestTime = min(current, elapsedSeconds)
        } else {
            bestTime = elapsedSeconds
        }
        let updated = PersonalRecord(
            recordName: existing.recordName,
            mode: existing.mode,
            difficulty: existing.difficulty,
            bestTimeSeconds: bestTime,
            totalTimeSeconds: existing.totalTimeSeconds + elapsedSeconds,
            completedCount: existing.completedCount + 1,
            lastUpdatedAt: clock(),
            completedPuzzleIds: ids
        )
        try await upsert(updated)
        return updated
    }

    static func recordName(mode: String, difficulty: String) -> String {
        "\(mode)-\(difficulty)"
    }
}

// MARK: - Mapper

internal enum PersonalRecordMapper {

    static func payload(from record: PersonalRecord) -> RecordPayload {
        var fields: [String: RecordValue] = [
            PersonalRecordStore.Field.mode: .string(record.mode),
            PersonalRecordStore.Field.difficulty: .string(record.difficulty),
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
            case .string(let mode) = payload.fields[PersonalRecordStore.Field.mode],
            case .string(let difficulty) = payload.fields[PersonalRecordStore.Field.difficulty],
            case .int(let total) = payload.fields[PersonalRecordStore.Field.totalTimeSeconds],
            case .int(let count) = payload.fields[PersonalRecordStore.Field.completedCount],
            case .date(let last) = payload.fields[PersonalRecordStore.Field.lastUpdatedAt]
        else {
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
