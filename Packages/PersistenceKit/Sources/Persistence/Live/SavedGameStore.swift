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
internal import SudokuGameState
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
        do {
            existing = try await gateway.fetch(recordName: recordName)
        } catch {
            await telemetry.observe(.gameSaveFailed(puzzleId: puzzleId, reason: Self.fetchFailedReason))
            existing = nil
        }
        if let existing {
            let puzzle = try await puzzleLoader(puzzleId)
            return try SavedGameMapper.snapshot(from: existing, puzzle: puzzle)
        }
        let puzzle = try await puzzleLoader(puzzleId)
        let session = GameSession(puzzle: puzzle)
        // #675: no eager seed-write here. A prior version best-effort-saved a
        // virgin idle snapshot immediately, so any board that was merely
        // mounted then abandoned before the first move left behind an
        // inProgress "0:00 elapsed" record forever offered as a resume
        // candidate. `GameViewModel` already persists on the first real
        // mutation (`scheduleSave()`) or on pause (`flush()`); a session that
        // never reaches either is correctly represented by NO record — there
        // is nothing to resume. This also sidesteps the #512 CR data-loss
        // concern (a failed fetch can't confirm a remote record is absent,
        // so writing here could clobber a real save) without needing a
        // `fetchFailed` branch: no write, no clobber.
        return await session.snapshot()
    }

    /// Fetch the SavedGame snapshot for `puzzleId` **without** creating one on
    /// absence. Unlike `loadOrCreate`, this distinguishes **confirmed
    /// absence** (returns `nil`) from **fetch failure, existence unknown**
    /// (throws) — the fetch error is propagated, never swallowed.
    ///
    /// `loadOrCreate`'s swallow-to-create semantics are correct for
    /// resume/new-game callers (a board that can't confirm a save must still
    /// be playable). They are WRONG for completed-game re-open callers
    /// (Sudoku's completed-card tap, past-day strip taps): a transient CK
    /// fetch error there must not synthesize a virgin
    /// `.completion(elapsedSeconds: 0, mistakeCount: 0)` for a legitimately
    /// completed game — #830. Those callers use `loadIfExists` instead and
    /// treat both `nil` and a thrown error as "fall back to `.board`"
    /// (#379 contract).
    func loadIfExists(
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> GameSessionSnapshot? {
        let recordName = Self.recordName(for: puzzleId, mode: mode)
        guard let existing = try await gateway.fetch(recordName: recordName) else {
            return nil
        }
        let puzzle = try await puzzleLoader(puzzleId)
        return try SavedGameMapper.snapshot(from: existing, puzzle: puzzle)
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
            // #544: gateway uses `.allKeys` save policy (last-write-wins) so
            // `CKError.serverRecordChanged` is never raised. The old
            // RetryHarness + ConflictResolver merge path was unreachable in
            // production and has been removed (SDD-005 §6).
            let payload = SavedGameMapper.payload(
                from: snapshot,
                recordName: recordName,
                puzzleId: puzzleId,
                mode: mode,
                difficulty: difficulty,
                lastModifiedAt: clock(),
                schemaVersion: Self.currentSchemaVersion
            )
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
