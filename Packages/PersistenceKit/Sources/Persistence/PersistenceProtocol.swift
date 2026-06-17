// PersistenceProtocol — the VM-facing seam for CloudKit Private DB.
//
// Per docs/v1/design.md §How.5.4. M5 (issue #65): the protocol takes typed
// `Mode` / `Difficulty` from SudokuEngine rather than raw `String`. The CK
// wire format remains string-based — mappers do the `.rawValue` conversion
// at the storage seam (`SavedGameMapper`, `PersonalRecordMapper`,
// `LivePrivateCKGateway.translate`).
//
// All methods are `async throws`; protocol is `Sendable` so existential
// `any PersistenceProtocol` can cross actor boundaries (Phase 8 ViewModels).

public import Foundation
public import SudokuGameState
public import SudokuEngine

public protocol PersistenceProtocol: Sendable {
    /// One-time CloudKit zone provisioning + subscription install. Issue #196:
    /// must be called from `RootViewModel.bootstrap()` once per app launch
    /// before any read/write — fresh iCloud accounts otherwise hit
    /// "Zone Not Found" (CKError 26) on every operation. Implementations are
    /// idempotent (safe to call multiple times; gateway no-ops after first
    /// success).
    func bootstrap() async throws

    /// Most-recently-modified `status == "inProgress"` SavedGame across all
    /// modes/difficulties. Used by RootViewModel to show "Resume".
    func latestInProgress() async throws -> SavedGameSummary?

    /// Load the in-progress SavedGame for `puzzleId`, or seed a fresh one
    /// from a default GameSession for that puzzle if none exists.
    func loadOrCreate(
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> GameSessionSnapshot

    /// Persist the current snapshot. Debounced upstream by the VM; the
    /// store itself is idempotent on the same `(puzzleId, mode, difficulty)`.
    ///
    /// Identity primitives are passed alongside the snapshot because
    /// `GameSessionSnapshot` carries `Puzzle` but not "daily vs practice"
    /// nor a user-facing `puzzleId`. The VM holds these on
    /// `GameViewModel.identity` and forwards them here. Per impl-notes
    /// 2026-05-20_wave-2-blocker-fixes §B2 — replaces the prior
    /// `save(_:)` overload whose seed-fallback wrote to a wrong record name.
    func save(
        _ snapshot: GameSessionSnapshot,
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws

    /// Flip `status` to `"completed"` for the given summary's record.
    func markCompleted(_ summary: SavedGameSummary) async throws

    /// Hard-delete a SavedGame (used when the player explicitly abandons).
    func deleteAbandoned(recordName: String) async throws

    /// puzzleIds of all `mode == "daily" && status == "completed"` records
    /// for the given UTC date. Seeds GameCenterSink's local dedup cache.
    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String>

    /// Fetch the PersonalRecord for `(mode, difficulty)`; returns an empty
    /// record if none exists yet (never throws on first read).
    func fetchPersonalRecord(
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> PersonalRecord

    /// Upsert. Implementations apply per-field LWW on server conflict
    /// (§How.6.7) and the "same puzzleId no rescore" dedup (§How.2 末段).
    func upsertPersonalRecord(_ record: PersonalRecord) async throws
}
