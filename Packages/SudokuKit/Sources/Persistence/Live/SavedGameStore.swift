// SavedGameStore — maps `GameSessionSnapshot` ↔ `RecordPayload` for the
// CloudKit `SavedGame` record type (§How.2).
//
// The store sits behind `PersistenceProtocol.save / loadOrCreate /
// markCompleted / deleteAbandoned / latestInProgress` and emits
// `.gameSaved` / `.gameSaveFailed` Telemetry on save attempts.
//
// `loadOrCreate` is asked to surface a `GameSessionSnapshot` for a
// `puzzleId` it may have never seen. Because Phase 5 ships before Phase 6
// (PuzzleStore), the store takes a `puzzleLoader` closure: tests inject a
// fixed `Puzzle`; in the App composition root Phase 6 wires this to
// `PuzzleStore.puzzle(for:)`.

internal import Foundation
internal import GameState
internal import SudokuEngine
internal import Telemetry

internal actor SavedGameStore: Sendable {

    public typealias PuzzleLoader = @Sendable (String) async throws -> Puzzle

    // MARK: - Field keys (§How.2)

    enum Field {
        static let puzzleId = "puzzleId"
        static let mode = "mode"
        static let difficulty = "difficulty"
        static let boardState = "boardState"
        static let notesState = "notesState"
        static let undoStack = "undoStack"
        static let startedAt = "startedAt"
        static let lastModifiedAt = "lastModifiedAt"
        static let elapsedSeconds = "elapsedSeconds"
        static let status = "status"
        static let generatorVersion = "generatorVersion"
        static let schemaVersion = "schemaVersion"
    }

    static let currentSchemaVersion = 1

    // MARK: - Deps

    private let gateway: any PrivateCKGateway
    private let telemetry: Telemetry
    private let puzzleLoader: PuzzleLoader
    private let clock: @Sendable () -> Date

    init(
        gateway: any PrivateCKGateway,
        telemetry: Telemetry,
        puzzleLoader: @escaping PuzzleLoader,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.gateway = gateway
        self.telemetry = telemetry
        self.puzzleLoader = puzzleLoader
        self.clock = clock
    }

    // MARK: - API

    func latestInProgress() async throws -> SavedGameSummary? {
        let payloads = try await gateway.query(
            .statusEquals(recordType: PrivateCKConstants.savedGameRecordType, status: "inProgress")
        )
        let summaries = payloads.compactMap(SavedGameMapper.summary(from:))
        return summaries.max { $0.lastModifiedAt < $1.lastModifiedAt }
    }

    func loadOrCreate(
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> GameSessionSnapshot {
        let recordName = Self.recordName(for: puzzleId, mode: mode)
        if let existing = try await gateway.fetch(recordName: recordName) {
            let puzzle = try await puzzleLoader(puzzleId)
            return try SavedGameMapper.snapshot(from: existing, puzzle: puzzle)
        }
        let puzzle = try await puzzleLoader(puzzleId)
        let session = GameSession(puzzle: puzzle)
        let snapshot = await session.snapshot()
        try await save(
            snapshot,
            puzzleId: puzzleId,
            mode: mode,
            difficulty: difficulty,
            recordName: recordName
        )
        return snapshot
    }

    /// Qualified save — `mode` cannot be inferred from `GameSessionSnapshot`
    /// alone (the snapshot carries `Puzzle` but not "daily vs practice").
    /// The VM layer holds the mode and calls this variant. The previously
    /// existing seed-fallback `save(_:)` overload was removed per impl-notes
    /// 2026-05-20_wave-2-blocker-fixes §B2 — it wrote to the wrong record
    /// name and created orphan records on every save.
    func save(
        _ snapshot: GameSessionSnapshot,
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws {
        let recordName = Self.recordName(for: puzzleId, mode: mode)
        try await save(
            snapshot,
            puzzleId: puzzleId,
            mode: mode,
            difficulty: difficulty,
            recordName: recordName
        )
    }

    func markCompleted(_ summary: SavedGameSummary) async throws {
        guard let existing = try await gateway.fetch(recordName: summary.recordName) else {
            throw PersistenceError.underlying(
                domain: "Persistence",
                code: 404,
                description: "markCompleted: record \(summary.recordName) not found"
            )
        }
        var fields = existing.fields
        fields[Field.status] = .string("completed")
        fields[Field.lastModifiedAt] = .date(clock())
        let updated = RecordPayload(
            recordType: existing.recordType,
            recordName: existing.recordName,
            fields: fields
        )
        try await gateway.save(updated)
    }

    func deleteAbandoned(recordName: String) async throws {
        try await gateway.delete(recordName: recordName)
    }

    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> {
        let prefix = UTCDay.string(from: date)
        let payloads = try await gateway.query(.dailyCompletedOn(dayPrefix: prefix))
        var ids: Set<String> = []
        for payload in payloads {
            if case .string(let value) = payload.fields[Field.puzzleId] {
                ids.insert(value)
            }
        }
        return ids
    }

    // MARK: - Internal save

    private func save(
        _ snapshot: GameSessionSnapshot,
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty,
        recordName: String
    ) async throws {
        let now = clock()
        let payload = SavedGameMapper.payload(
            from: snapshot,
            recordName: recordName,
            puzzleId: puzzleId,
            mode: mode,
            difficulty: difficulty,
            lastModifiedAt: now,
            schemaVersion: Self.currentSchemaVersion
        )
        do {
            try await gateway.save(payload)
            await telemetry.observe(.gameSaved(puzzleId: puzzleId))
        } catch let error as PersistenceError {
            await telemetry.observe(.gameSaveFailed(puzzleId: puzzleId, reason: Self.reason(for: error)))
            throw error
        } catch {
            await telemetry.observe(.gameSaveFailed(puzzleId: puzzleId, reason: "underlying"))
            throw error
        }
    }

    // MARK: - Helpers

    static func recordName(for puzzleId: String, mode: Mode) -> String {
        "\(mode.rawValue)-\(puzzleId)"
    }

    private static func reason(for error: PersistenceError) -> String {
        switch error {
        case .iCloudNotSignedIn: return "iCloudNotSignedIn"
        case .iCloudSignedOutDuringSession: return "iCloudSignedOutDuringSession"
        case .iCloudAccountChanged: return "iCloudAccountChanged"
        case .quotaExceeded: return "quotaExceeded"
        case .zoneNotProvisioned: return "zoneNotProvisioned"
        case .syncConflict: return "syncConflict"
        case .schemaVersionTooNew: return "schemaVersionTooNew"
        case .underlying: return "underlying"
        }
    }
}
