// MinesweeperSavedGameStore — maps `MinesweeperSessionSnapshot` ↔
// `RecordPayload` for the Minesweeper `SavedGame` CloudKit record type
// (#455; structural mirror of Sudoku's `SavedGameStore`).
//
// Built on the shared public `PrivateCKGateway` seam: record-type name
// `"SavedGame"` is safe to reuse — each app owns its own CKContainer
// (`PrivateCKConstants` doc), so the Sudoku and MS records never collide.
//
// Wire shape (this is the `cloudkit/minesweeper.ckdb` schema contract):
//   difficulty      String      Difficulty.rawValue (beginner/intermediate/expert)
//   seed            Int(64)     UInt64 bit-pattern (see `seed` mapping below)
//   mode            String      game-mode qualifier ("daily" / "practice")
//   elapsedSeconds  Int(64)
//   status          String      "inProgress" / "completed"
//   lastModifiedAt  Date/Time
//   schemaVersion   Int(64)     1
//   stateBlob       Bytes       JSON-encoded MinesweeperSessionSnapshot
//
// Index contract (part of the .ckdb spec — #463 CR / #464): `latestInProgress()`
// issues `NSPredicate("status == %@")` on the live gateway, so the schema
// marks `status` QUERYABLE — and nothing else. `recordName` needs no index
// (Sudoku Production runs the identical statusEquals query without one), and
// `lastModifiedAt` needs no sortable index — the max-by is client-side.
//
// Seed mapping: `RecordValue.int(Int)` is the only integer wire type, and
// CloudKit's Int(64) is signed — a board seed is `UInt64`, so it crosses the
// wire as its `Int64` bit-pattern (`Int64(bitPattern:)` out,
// `UInt64(bitPattern:)` back). Lossless both ways for every UInt64.
//
// Conflict scope (deliberate MVP trim, #463 CR; decided in step 4): `save` is
// a bare `gateway.save` — a cross-device `.syncConflict` THROWS, and the VM's
// `persistCurrentState()` funnels it (never interrupts gameplay). Sudoku's
// RetryHarness + ConflictResolver remain overkill for MS v1.
//
// Constructed by `MinesweeperAppComposition.live()` (#455 step 4) over
// `PrivateCKGatewayFactory`; the `SavedGame` schema deployed to both CloudKit
// environments 2026-06-10 (cloudkit/minesweeper.ckdb).

public import Foundation
public import MinesweeperEngine
public import MinesweeperGameState
public import Persistence
public import Telemetry

public actor MinesweeperSavedGameStore {

    // MARK: - Field keys (mirror Sudoku's SavedGameStore.Field)

    enum Field {
        static let difficulty = "difficulty"
        static let seed = "seed"
        static let mode = "mode"
        static let elapsedSeconds = "elapsedSeconds"
        static let status = "status"
        static let lastModifiedAt = "lastModifiedAt"
        static let schemaVersion = "schemaVersion"
        static let stateBlob = "stateBlob"
    }

    static let currentSchemaVersion = 1

    // MARK: - Deps

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
    /// save ("daily" / "practice") — the snapshot itself carries no mode,
    /// mirroring Sudoku's qualified `save(_:puzzleId:mode:difficulty:)`.
    public func save(
        _ snapshot: MinesweeperSessionSnapshot,
        modeRaw: String,
        recordName: String
    ) async throws {
        do {
            let blob = try JSONEncoder().encode(snapshot)
            let payload = RecordPayload(
                recordType: PrivateCKConstants.savedGameRecordType,
                recordName: recordName,
                fields: [
                    Field.difficulty: .string(snapshot.difficulty.rawValue),
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
            // Mirror Sudoku's SavedGameStore: a failed save is observable
            // (telemetry funnel) but still thrown so the caller can react.
            await telemetry?.observe(
                .gameSaveFailed(puzzleId: recordName, reason: String(describing: error))
            )
            throw error
        }
    }

    /// Most recently touched non-completed save, or nil. Feeds MS's
    /// `fetchResume` closure (#460 seam). Stale dailies are filtered out:
    /// a daily from a PAST day can't be resumed meaningfully (the hub already
    /// rotated), so dailies from today (`>=` also admits future-dated names —
    /// unreachable, nothing writes them) and any practice save are the
    /// candidates. Mirrors Sudoku's #228 fix; the day rides in the
    /// `daily-<YYYY-MM-DD>-<difficulty>` recordName scheme.
    ///
    /// iCloud-signed-out / not-authenticated fetch failures are mapped to `nil`
    /// (no resumable game) so the Home resume pill degrades gracefully offline
    /// (#515). Schema / decode errors are NOT caught here — they propagate so
    /// the caller can hide or delete a broken candidate (per #463 CR contract).
    public func latestInProgress() async throws -> MinesweeperSavedGameSummary? {
        let payloads: [RecordPayload]
        do {
            payloads = try await gateway.query(
                .statusEquals(recordType: PrivateCKConstants.savedGameRecordType, status: "inProgress")
            )
        } catch {
            if UserFacingError.classify(error) == .iCloudSignedOut { return nil }
            throw error
        }
        let todayUTC = UTCDay.string(from: clock())
        return payloads
            .compactMap(Self.summary(from:))
            .filter { summary in
                guard summary.modeRaw == GameModeRaw.daily else { return true }
                guard let day = Self.dailyDay(fromRecordName: summary.recordName) else { return true }
                return day >= todayUTC
            }
            .max { $0.lastModifiedAt < $1.lastModifiedAt }
    }

    /// `daily-<YYYY-MM-DD>-<difficulty>` → `YYYY-MM-DD`; nil for any other
    /// shape (treated as non-stale, mirroring Sudoku's tolerant parse).
    /// `public` (not `internal`): #700's achievement streak/full-spectrum
    /// facts reuse this exact day-parse in `MinesweeperUI` rather than
    /// duplicating the format logic.
    public static func dailyDay(fromRecordName recordName: String) -> String? {
        guard recordName.hasPrefix("daily-") else { return nil }
        let day = recordName.dropFirst("daily-".count).prefix(10)
        guard day.count == 10,
              day[day.index(day.startIndex, offsetBy: 4)] == "-",
              day[day.index(day.startIndex, offsetBy: 7)] == "-"
        else { return nil }
        return String(day)
    }

    /// Decode the full snapshot for a known record; nil when the record is
    /// genuinely absent, is terminal (completed/failed — not resumable, #700
    /// CR), or iCloud is signed out (#515 — signed-out fetch degrades to
    /// "no resumable game" so the Home/resume UI doesn't dead-end).
    /// A blob written by a NEWER schema throws `.schemaVersionTooNew`; a corrupt
    /// blob propagates its decode error — both distinguishable from "no save",
    /// so the caller can hide/delete a broken candidate instead of surfacing a
    /// resume pill that loads nothing (#463 CR). The caller rebuilds the live
    /// board via `MinesweeperSession.restore(from:)`.
    public func loadInProgress(recordName: String) async throws -> MinesweeperSessionSnapshot? {
        guard let payload = try await fetchPayload(recordName: recordName) else { return nil }
        // #700 CR: a terminal record ("completed" / "failed") is not
        // resumable — mirror `latestInProgress()`'s status filter. Handing a
        // `.won` session to a fresh ViewModel (whose per-instance latches are
        // unset) would re-run win side effects, inflating the non-idempotent
        // achievement win tally. A missing status field stays resumable
        // (tolerant, matching `dailyDay`'s tolerant-parse philosophy).
        if case .string(let status) = payload.fields[Field.status],
           status != "inProgress" {
            return nil
        }
        return try Self.decodeSnapshot(from: payload)
    }

    /// Decode the stored snapshot for `recordName` regardless of `status`
    /// (#841). Unlike `loadInProgress`, this does NOT exclude terminal
    /// records — it exists specifically to recover a "failed" daily's
    /// persisted mine layout for the free-replay loader (`.replayDailyBoard`),
    /// which needs the exact board the player already saw once, not a
    /// resumable in-progress game. Same iCloud-signed-out /
    /// schema-too-new / corrupt-blob handling as `loadInProgress`, minus the
    /// status gate.
    public func loadSnapshot(recordName: String) async throws -> MinesweeperSessionSnapshot? {
        guard let payload = try await fetchPayload(recordName: recordName) else { return nil }
        return try Self.decodeSnapshot(from: payload)
    }

    /// Shared fetch step for `loadInProgress` / `loadSnapshot`: resolve the
    /// record, degrading a signed-out iCloud fetch to "no record" (#515)
    /// rather than throwing.
    private func fetchPayload(recordName: String) async throws -> RecordPayload? {
        do {
            return try await gateway.fetch(recordName: recordName)
        } catch {
            if UserFacingError.classify(error) == .iCloudSignedOut { return nil }
            throw error
        }
    }

    /// Shared decode step: schema-too-new throws (distinguishable from "no
    /// save" so a caller can hide/delete a broken candidate), a missing blob
    /// is `nil`, otherwise decode the `MinesweeperSessionSnapshot`.
    private static func decodeSnapshot(from payload: RecordPayload) throws -> MinesweeperSessionSnapshot? {
        if case .int(let version) = payload.fields[Field.schemaVersion],
           version > Self.currentSchemaVersion {
            throw PersistenceError.schemaVersionTooNew(
                expected: Self.currentSchemaVersion,
                found: version
            )
        }
        guard case .data(let blob) = payload.fields[Field.stateBlob] else { return nil }
        return try JSONDecoder().decode(MinesweeperSessionSnapshot.self, from: blob)
    }

    /// Flip a save to "completed" so `latestInProgress()` stops surfacing it.
    public func markCompleted(recordName: String) async throws {
        guard let existing = try await gateway.fetch(recordName: recordName) else {
            throw PersistenceError.underlying(
                domain: "MinesweeperPersistence",
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
    // Centralized so step 4 cannot reinvent an ad-hoc scheme — Sudoku's store
    // grew its `recordName(for:mode:)` helper after a freehand overload wrote
    // to the wrong name and orphaned a record per save (#463 CR / Sudoku
    // SavedGameStore scar). One record per daily board; one resumable slot
    // per practice difficulty.

    /// `daily-<YYYY-MM-DD>-<difficulty>` — identical to
    /// `MinesweeperDaily.puzzleId(day:difficulty:)`, so the saved record,
    /// the hub card, and stale-daily detection all share one identity.
    public static func recordName(dailyDay day: String, difficulty: Difficulty) -> String {
        MinesweeperDaily.puzzleId(day: day, difficulty: difficulty)
    }

    /// `practice-<difficulty>` — a singleton resumable slot per difficulty
    /// (a new practice game of the same difficulty overwrites the old save).
    public static func recordName(practice difficulty: Difficulty) -> String {
        "practice-\(difficulty.rawValue)"
    }

    // MARK: - Mapping

    /// Status wire values. Epic 8 (SDD-003): `.lost` maps to `"failed"` (a
    /// distinct third state from `"completed"`) so the daily hub can surface a
    /// Failed card. `.won` stays `"completed"`. Everything else (idle / playing /
    /// paused) is a resumable `"inProgress"` save.
    /// Migration note (v2.6 cutover): records saved BEFORE SDD-003 Epic 8
    /// mapped .lost to "completed" — historical losses read back as
    /// completions. Accepted without migration: MS never shipped publicly
    /// (TestFlight-internal records only). New saves are three-state.
    static func wireStatus(for status: MinesweeperSessionStatus) -> String {
        switch status {
        case .won: return "completed"
        case .lost: return "failed"
        default: return "inProgress"
        }
    }

    /// puzzleIds of `mode == "daily" && status == "failed"` records for the
    /// given UTC date. Feeds `MinesweeperDailyHubViewModel.bootstrap()` so
    /// failed cards render a third distinct state. Mirrors `fetchCompletedDailyIds`
    /// structure: graceful-degrade on query failure is the caller's responsibility.
    public func fetchFailedDailyIds(for date: Date) async throws -> Set<String> {
        let today = UTCDay.string(from: date)
        let payloads = try await gateway.query(
            .statusEquals(recordType: PrivateCKConstants.savedGameRecordType, status: "failed")
        )
        return Set(
            payloads
                .compactMap(Self.summary(from:))
                .filter { summary in
                    guard summary.modeRaw == GameModeRaw.daily else { return false }
                    guard let day = Self.dailyDay(fromRecordName: summary.recordName) else { return false }
                    return day == today
                }
                .map(\.recordName)
        )
    }

    /// puzzleIds of `mode == "daily" && status == "completed"` records for the
    /// given UTC date. Feeds `MinesweeperDailyHubViewModel.fillCompletionAndFailureOverlay`
    /// (#816). MS's hub used to read completed ids via the shared Sudoku-shaped
    /// `PersistenceProtocol.fetchCompletedDailyIds`, whose CK predicate is
    /// `mode == %@ AND status == %@ AND puzzleId BEGINSWITH %@` — but MS's
    /// `SavedGame` schema (`cloudkit/minesweeper.ckdb`) has no `puzzleId` field
    /// and only `status` is QUERYABLE, so that query always threw and the green
    /// check never appeared. Mirrors `fetchFailedDailyIds`'s structure exactly:
    /// query the queryable `status` field only, then filter mode/day client-side.
    public func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> {
        let today = UTCDay.string(from: date)
        let payloads = try await gateway.query(
            .statusEquals(recordType: PrivateCKConstants.savedGameRecordType, status: "completed")
        )
        return Set(
            payloads
                .compactMap(Self.summary(from:))
                .filter { summary in
                    guard summary.modeRaw == GameModeRaw.daily else { return false }
                    guard let day = Self.dailyDay(fromRecordName: summary.recordName) else { return false }
                    return day == today
                }
                .map(\.recordName)
        )
    }

    /// Single-query, day-bucketed sibling of `fetchCompletedDailyIds(for:)`
    /// (#915). That method's CK query is date-agnostic — `status ==
    /// "completed"` is the only queryable predicate the schema offers (see its
    /// doc) — so a caller needing several days back-to-back was issuing one
    /// BYTE-IDENTICAL CK query per day and throwing away every result except
    /// the one matching that day. `MinesweeperDailyHubViewModel.fetchWeekWindow`
    /// (the 7-day rolling week-strip window) is exactly that caller: this
    /// collapses its 7 redundant reads into 1 by running the query once and
    /// bucketing every daily-completed record by its UTC day
    /// (`dailyDay(fromRecordName:)`), keyed the same way
    /// `UTCDay.string(from:)` formats a date. `fetchCompletedDailyIds(for:)`
    /// itself is UNCHANGED — its other caller (`MinesweeperDailyOpenGuardView`'s
    /// today-only re-check) genuinely needs just one day, so a single query
    /// already covers it.
    public func fetchCompletedDailyIdsByDay() async throws -> [String: Set<String>] {
        let payloads = try await gateway.query(
            .statusEquals(recordType: PrivateCKConstants.savedGameRecordType, status: "completed")
        )
        var byDay: [String: Set<String>] = [:]
        for summary in payloads.compactMap(Self.summary(from:)) {
            guard summary.modeRaw == GameModeRaw.daily else { continue }
            guard let day = Self.dailyDay(fromRecordName: summary.recordName) else { continue }
            byDay[day, default: []].insert(summary.recordName)
        }
        return byDay
    }

    static func summary(from payload: RecordPayload) -> MinesweeperSavedGameSummary? {
        guard
            case .string(let difficultyRaw) = payload.fields[Field.difficulty],
            let difficulty = Difficulty(rawValue: difficultyRaw),
            case .int(let seedBits) = payload.fields[Field.seed],
            case .string(let modeRaw) = payload.fields[Field.mode],
            case .int(let elapsed) = payload.fields[Field.elapsedSeconds],
            case .string(let status) = payload.fields[Field.status],
            case .date(let lastModifiedAt) = payload.fields[Field.lastModifiedAt]
        else { return nil }
        return MinesweeperSavedGameSummary(
            recordName: payload.recordName,
            difficulty: difficulty,
            seed: UInt64(bitPattern: Int64(seedBits)),
            modeRaw: modeRaw,
            elapsedSeconds: elapsed,
            lastModifiedAt: lastModifiedAt,
            status: status
        )
    }
}
