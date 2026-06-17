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
        /// SDD-003 Epic 3 — cumulative conflicting-placement counter.
        static let mistakeCount = "mistakeCount"
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
        // Issue #228 (option E): filter out stale daily saves whose embedded
        // date is older than today (UTC). Practice saves never expire; today's
        // daily is unaffected. Cleanup of the stale records themselves is a
        // separate follow-up — this filter only hides them from the resume
        // candidate set so newer non-stale saves are not masked.
        let todayUTC = UTCDay.string(from: clock())
        let eligible = summaries.filter { summary in
            guard summary.mode == .daily else { return true }
            guard let day = Self.extractDailyDay(from: summary.puzzleId) else { return true }
            return day >= todayUTC
        }
        return eligible.max { $0.lastModifiedAt < $1.lastModifiedAt }
    }

    /// Pull the `YYYY-MM-DD` prefix from a daily puzzleId. Mirrors
    /// `GameCenterClient/SubmitGuards.extractDailyDay` — duplicated rather
    /// than re-exported because crossing the PersistenceKit ↔ GameCenterKit
    /// dep boundary for a 5-line helper would invert the dep graph
    /// (foundations.md §2 forbids upward arrows).
    private static func extractDailyDay(from puzzleId: String) -> String? {
        // Daily format: "YYYY-MM-DD-{difficulty}" (see PuzzleIdentity.daily).
        // Anything else (practice ids, malformed) → nil → treat as non-stale.
        let prefix = puzzleId.prefix(10)
        guard prefix.count == 10,
              prefix.allSatisfy({ $0.isASCII }),
              prefix[prefix.index(prefix.startIndex, offsetBy: 4)] == "-",
              prefix[prefix.index(prefix.startIndex, offsetBy: 7)] == "-"
        else { return nil }
        return String(prefix)
    }

    func loadOrCreate(
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> GameSessionSnapshot {
        let recordName = Self.recordName(for: puzzleId, mode: mode)
        // Local-first: iCloud unavailability must never prevent puzzle load.
        // Any fetch error (notAuthenticated, network, zoneNotProvisioned) is
        // treated as "could not confirm an existing save" so the deterministic
        // puzzleLoader path is always reachable. The swallowed error is
        // reported via telemetry so the event stays observable in OSLog (#512).
        let existing: RecordPayload?
        var fetchFailed = false
        do {
            existing = try await gateway.fetch(recordName: recordName)
        } catch {
            await telemetry.observe(.gameSaveFailed(puzzleId: puzzleId, reason: Self.fetchFailedReason))
            existing = nil
            fetchFailed = true
        }
        if let existing {
            let puzzle = try await puzzleLoader(puzzleId)
            return try SavedGameMapper.snapshot(from: existing, puzzle: puzzle)
        }
        let puzzle = try await puzzleLoader(puzzleId)
        let session = GameSession(puzzle: puzzle)
        let snapshot = await session.snapshot()
        // Data-loss guard (#512 CR): when the fetch failed we CANNOT confirm a
        // remote record is absent. A transient blip (network, not signed-out)
        // could hide a real in-progress save; persisting the fresh idle
        // snapshot here would clobber it. So skip the initial save entirely on
        // fetch failure — just return the snapshot for play. The VM persists on
        // the first move through the conflict-resolved save path, so a genuinely
        // new offline game still survives once the user acts.
        if !fetchFailed {
            // Best-effort seed of the new record; a save failure must not
            // prevent the caller from receiving the fresh local snapshot.
            try? await save(
                snapshot,
                puzzleId: puzzleId,
                mode: mode,
                difficulty: difficulty,
                recordName: recordName
            )
        }
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
        do {
            // §How.6.7: wrap the live save in RetryHarness; on a
            // `serverRecordChanged`-equivalent (`.syncConflict` from the
            // gateway) re-fetch, run ConflictResolver.resolve, and resubmit
            // the merged record. Budget: 2 retries; 3rd → throw.
            let initialPayload = SavedGameMapper.payload(
                from: snapshot,
                recordName: recordName,
                puzzleId: puzzleId,
                mode: mode,
                difficulty: difficulty,
                lastModifiedAt: clock(),
                schemaVersion: Self.currentSchemaVersion
            )
            // Holder isolates the retry-loop mutation from the Sendable
            // closure (Swift 6 strict concurrency: captured vars cannot be
            // mutated). The actor is the loop's effective owner so each
            // body invocation is serialized via `self`.
            let working = MutableRef(value: initialPayload)
            let gatewayRef = gateway
            let clockRef = clock
            try await RetryHarness.run(recordName: recordName) { _ in
                // Refresh `lastModifiedAt` per attempt so the resolver's
                // newer-wins tie-break treats the local side as advancing.
                var current = await working.get()
                current.fields[Field.lastModifiedAt] = .date(clockRef())
                await working.set(current)
                do {
                    try await gatewayRef.save(current)
                    return .success(())
                } catch PersistenceError.syncConflict {
                    guard let serverPayload = try await gatewayRef.fetch(recordName: recordName) else {
                        return .conflict
                    }
                    let merged = Self.merge(local: current, server: serverPayload)
                    await working.set(merged)
                    return .conflict
                }
            }
            await telemetry.observe(.gameSaved(puzzleId: puzzleId))
        } catch let error as PersistenceError {
            await telemetry.observe(.gameSaveFailed(puzzleId: puzzleId, reason: Self.reason(for: error)))
            throw error
        } catch {
            await telemetry.observe(.gameSaveFailed(puzzleId: puzzleId, reason: "underlying"))
            throw error
        }
    }

    // MARK: - Conflict merge

    /// Apply `ConflictResolver.resolve(local:server:)` at the payload layer.
    /// Both inputs are projected into the resolver-shaped snapshot using the
    /// existing wire encoding (see SavedGameMapper); the merged result is
    /// written back into the local payload's fields (preserving non-LWW
    /// fields like `puzzleId` / `mode` / `difficulty` / `startedAt`).
    private static func merge(local: RecordPayload, server: RecordPayload) -> RecordPayload {
        let localSnapshot = conflictSnapshot(from: local)
        let serverSnapshot = conflictSnapshot(from: server)
        let resolved = ConflictResolver.resolve(local: localSnapshot, server: serverSnapshot)
        var merged = local
        // #544: adopt the SERVER record's etag so the resubmit is an UPDATE
        // against the current change-tag (the local side was an etag-less fresh
        // payload, which is what triggered the conflict). Field values are
        // newer-wins via ConflictResolver above.
        merged.encodedSystemFields = server.encodedSystemFields
        merged.fields[Field.boardState] = .string(resolved.boardState)
        merged.fields[Field.notesState] = .data(resolved.notesState)
        merged.fields[Field.undoStack] = .data(resolved.undoStack)
        merged.fields[Field.elapsedSeconds] = .int(resolved.elapsedSeconds)
        merged.fields[Field.status] = .string(resolved.status)
        merged.fields[Field.lastModifiedAt] = .date(resolved.lastModifiedAt)
        return merged
    }

    private static func conflictSnapshot(from payload: RecordPayload) -> ConflictResolver.SavedGameSnapshot {
        let board: String
        if case .string(let value) = payload.fields[Field.boardState] { board = value } else { board = "" }
        let notes: Data
        if case .data(let value) = payload.fields[Field.notesState] { notes = value } else { notes = Data() }
        let undo: Data
        if case .data(let value) = payload.fields[Field.undoStack] { undo = value } else { undo = Data() }
        let elapsed: Int
        if case .int(let value) = payload.fields[Field.elapsedSeconds] { elapsed = value } else { elapsed = 0 }
        let status: String
        if case .string(let value) = payload.fields[Field.status] { status = value } else { status = "inProgress" }
        let lastModified: Date
        if case .date(let value) = payload.fields[Field.lastModifiedAt] {
            lastModified = value
        } else {
            lastModified = .distantPast
        }
        return ConflictResolver.SavedGameSnapshot(
            boardState: board,
            notesState: notes,
            undoStack: undo,
            elapsedSeconds: elapsed,
            status: status,
            lastModifiedAt: lastModified
        )
    }

    // MARK: - Helpers

    static func recordName(for puzzleId: String, mode: Mode) -> String {
        "\(mode.rawValue)-\(puzzleId)"
    }

    /// Telemetry `reason` token emitted when `loadOrCreate`'s fetch fails and
    /// the load falls back to a local-only snapshot (#512). Greppable contract,
    /// distinct from the `reason(for:)` mapping of save-time errors.
    private static let fetchFailedReason = "fetchFailed"

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

/// Tiny generic actor box so the RetryHarness's `@Sendable` closure can
/// hold mutable per-attempt state without violating Swift 6 captured-var
/// rules. Lives at file scope so it can be reused by sibling stores.
internal actor MutableRef<Value: Sendable> {
    private var value: Value
    init(value: Value) { self.value = value }
    func get() -> Value { value }
    func set(_ newValue: Value) { value = newValue }
}
