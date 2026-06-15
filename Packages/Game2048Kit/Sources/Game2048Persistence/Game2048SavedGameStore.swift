// Game2048SavedGameStore — maps `Game2048SessionSnapshot` ↔
// `RecordPayload` for the Tiles2048 `SavedGame` CloudKit record type.
// Mirrors MinesweeperSavedGameStore exactly; only the snapshot type,
// wire fields, and record-name scheme differ.
//
// Wire shape (this is the cloudkit/tiles2048.ckdb schema contract):
//   score           Int(64)     current score
//   moveCount       Int(64)     move count
//   seed            Int(64)     UInt64 bit-pattern (Int64 bitPattern)
//   mode            String      "daily" / "practice"
//   elapsedSeconds  Int(64)
//   status          String      "inProgress" / "completed"
//   lastModifiedAt  Date/Time
//   schemaVersion   Int(64)     1
//   stateBlob       Bytes       JSON-encoded Game2048SessionSnapshot
//
// Index contract: `latestInProgress()` issues
// `NSPredicate("status == %@")` via `.statusEquals`, so `status` must be
// QUERYABLE in the schema (see cloudkit/tiles2048.ckdb). Nothing else.
//
// Seed mapping: UInt64 seed crosses the wire as its Int64 bit-pattern
// (Int64(bitPattern:) out, UInt64(bitPattern:) back). Lossless.
//
// Stale-daily filter: 2048 Daily = one board per UTC day (same seed, one
// attempt). A daily from a PAST day can't be resumed (the hub rotated), so
// filter by `recordName` prefix like MS: `daily-<YYYY-MM-DD>` must be >=
// today. Practice gets one singleton slot (overwritten on each new game).
//
// CloudKit lazy contract: this store is constructed by composition root via
// `PrivateCKGatewayFactory.live(config: .tiles2048)`. The factory defers
// `CKContainer.default()` to first operation — an unentitled test runner
// that builds `.live()` never touches CloudKit.

public import Foundation
public import Game2048Engine
public import Game2048GameState
public import Persistence
public import Telemetry

public actor Game2048SavedGameStore {

    // MARK: - Field keys

    enum Field {
        static let score = "score"
        static let moveCount = "moveCount"
        static let seed = "seed"
        static let mode = "mode"
        static let elapsedSeconds = "elapsedSeconds"
        static let status = "status"
        static let lastModifiedAt = "lastModifiedAt"
        static let schemaVersion = "schemaVersion"
        static let stateBlob = "stateBlob"
    }

    static let currentSchemaVersion = 1

    // MARK: - Dependencies

    private let gateway: any PrivateCKGateway
    private let telemetry: Telemetry?
    private let clock: @Sendable () -> Date

    public init(
        gateway: any PrivateCKGateway,
        telemetry: Telemetry? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.gateway = gateway
        self.telemetry = telemetry
        self.clock = clock
    }

    // MARK: - API

    /// Persist an in-flight (or terminal) board. `modeRaw` qualifies the
    /// save ("daily" / "practice"). Mirrors MinesweeperSavedGameStore.save.
    public func save(
        _ snapshot: Game2048SessionSnapshot,
        modeRaw: String,
        recordName: String
    ) async throws {
        do {
            let blob = try JSONEncoder().encode(snapshot)
            let payload = RecordPayload(
                recordType: PrivateCKConstants.savedGameRecordType,
                recordName: recordName,
                fields: [
                    Field.score: .int(snapshot.score),
                    Field.moveCount: .int(snapshot.moveCount),
                    Field.seed: .int(Int(Int64(bitPattern: snapshot.seed))),
                    Field.mode: .string(modeRaw),
                    Field.elapsedSeconds: .int(snapshot.elapsedSeconds),
                    Field.status: .string(Self.wireStatus(for: snapshot.status)),
                    Field.lastModifiedAt: .date(clock()),
                    Field.schemaVersion: .int(Self.currentSchemaVersion),
                    Field.stateBlob: .data(blob),
                ]
            )
            try await gateway.save(payload)
            await telemetry?.observe(.gameSaved(puzzleId: recordName))
        } catch {
            await telemetry?.observe(
                .gameSaveFailed(puzzleId: recordName, reason: String(describing: error))
            )
            throw error
        }
    }

    /// Most recently touched non-completed save, or nil. Feeds 2048's
    /// `fetchResume` closure. Stale dailies filtered: a daily from a
    /// past day is skipped (the hub rotated). Mirrors MinesweeperSavedGameStore.
    public func latestInProgress() async throws -> Game2048SavedGameSummary? {
        let payloads = try await gateway.query(
            .statusEquals(recordType: PrivateCKConstants.savedGameRecordType, status: "inProgress")
        )
        let todayUTC = UTCDay.string(from: clock())
        return payloads
            .compactMap(Self.summary(from:))
            .filter { summary in
                guard summary.modeRaw == Game2048GameModeRaw.daily else { return true }
                guard let day = Self.dailyDay(fromRecordName: summary.recordName) else { return true }
                return day >= todayUTC
            }
            .max { $0.lastModifiedAt < $1.lastModifiedAt }
    }

    /// Decode the full snapshot for a known record; nil when absent.
    /// Mirrors MinesweeperSavedGameStore.loadInProgress.
    public func loadInProgress(recordName: String) async throws -> Game2048SessionSnapshot? {
        guard let payload = try await gateway.fetch(recordName: recordName) else { return nil }
        if case .int(let version) = payload.fields[Field.schemaVersion],
           version > Self.currentSchemaVersion {
            throw PersistenceError.schemaVersionTooNew(
                expected: Self.currentSchemaVersion,
                found: version
            )
        }
        guard case .data(let blob) = payload.fields[Field.stateBlob] else { return nil }
        return try JSONDecoder().decode(Game2048SessionSnapshot.self, from: blob)
    }

    /// Flip a save to "completed" so `latestInProgress()` stops surfacing it.
    public func markCompleted(recordName: String) async throws {
        guard let existing = try await gateway.fetch(recordName: recordName) else {
            throw PersistenceError.underlying(
                domain: "Game2048Persistence",
                code: 404,
                description: "markCompleted: record \(recordName) not found"
            )
        }
        var fields = existing.fields
        fields[Field.status] = .string("completed")
        fields[Field.lastModifiedAt] = .date(clock())
        try await gateway.save(
            RecordPayload(
                recordType: existing.recordType,
                recordName: existing.recordName,
                fields: fields
            )
        )
    }

    // MARK: - Record names
    //
    // One record per daily board (seed is fixed per UTC day);
    // one resumable slot for practice (overwritten each new game).

    /// `daily-<YYYY-MM-DD>` — one board per UTC day (2048 has no difficulty).
    public static func recordName(dailyDay day: String) -> String {
        "daily-\(day)"
    }

    /// `practice` — singleton slot; a new practice game overwrites the slot.
    public static let practiceRecordName = "practice"

    /// Derives the correct record name from mode + current date.
    public static func recordName(mode: Game2048GameModeRaw.Type = Game2048GameModeRaw.self, modeRaw: String, now: Date = Date()) -> String {
        switch modeRaw {
        case Game2048GameModeRaw.daily: return recordName(dailyDay: UTCDay.string(from: now))
        default: return practiceRecordName
        }
    }

    // MARK: - Internal helpers

    /// `daily-<YYYY-MM-DD>` → `YYYY-MM-DD`; nil for any other shape.
    static func dailyDay(fromRecordName recordName: String) -> String? {
        guard recordName.hasPrefix("daily-") else { return nil }
        let day = recordName.dropFirst("daily-".count).prefix(10)
        guard day.count == 10,
              day[day.index(day.startIndex, offsetBy: 4)] == "-",
              day[day.index(day.startIndex, offsetBy: 7)] == "-"
        else { return nil }
        return String(day)
    }

    /// OQ-004-3: stuck = end of run, no Failed state.
    /// `.stuck` → "completed" (the run is over; it was a natural termination).
    static func wireStatus(for status: Game2048SessionStatus) -> String {
        switch status {
        case .stuck: return "completed"
        default: return "inProgress"
        }
    }

    static func summary(from payload: RecordPayload) -> Game2048SavedGameSummary? {
        guard
            case .int(let seedBits) = payload.fields[Field.seed],
            case .string(let modeRaw) = payload.fields[Field.mode],
            case .int(let elapsed) = payload.fields[Field.elapsedSeconds],
            case .int(let score) = payload.fields[Field.score],
            case .string(let status) = payload.fields[Field.status],
            case .date(let lastModifiedAt) = payload.fields[Field.lastModifiedAt]
        else { return nil }
        let moveCount: Int
        if case .int(let moves) = payload.fields[Field.moveCount] {
            moveCount = moves
        } else {
            moveCount = 0
        }
        return Game2048SavedGameSummary(
            recordName: payload.recordName,
            seed: UInt64(bitPattern: Int64(seedBits)),
            modeRaw: modeRaw,
            score: score,
            moveCount: moveCount,
            elapsedSeconds: elapsed,
            lastModifiedAt: lastModifiedAt,
            status: status
        )
    }
}
