// UITestShowcasePersistence — #1054, DEBUG-only fixed-snapshot injection for
// `PersistenceProtocol`, gated by the `-uitest-route board:showcase` launch
// argument (`GameAppKit.UITestLaunchArg.showcaseBoardRouteKey`). Wraps the
// live persistence and, for the ONE fixed `SudokuShowcaseBoard.puzzleId`,
// hands back the deterministic showcase snapshot instead of touching
// CloudKit — so the App Store 03-board marketing capture is reproducible
// without depending on (or polluting) a real saved game. Every write for
// that id no-ops; every other puzzleId delegates to the wrapped live
// persistence unchanged. Mirrors `UITestSeededCompletedDailyPersistence`'s
// wrapper shape and injection point. Absent from Release builds via the
// `#if DEBUG` guard.

internal import Foundation
internal import SudokuEngine
internal import SudokuGameState
internal import SudokuPersistence
internal import Persistence
#if DEBUG
internal import GameAppKit
// `SudokuShowcaseBoard` (the fixed snapshot builder + `puzzleId`) lives in
// SudokuUI — only needed for this DEBUG-only wrapper.
internal import SudokuUI
#endif

#if DEBUG

/// Wraps a live `PersistenceProtocol`; for `SudokuShowcaseBoard.puzzleId`,
/// `loadOrCreate` / `loadIfExists` return the fixed showcase snapshot and
/// `save` / `markCompleted` for that id no-op — the showcase board must
/// never reach CloudKit. `deleteAbandoned` has no puzzleId to match against
/// and is never reachable from this board's lifecycle (the board never
/// fully fills, so `complete()` never fires, and `save` never writes a
/// record for it to begin with) — delegates unconditionally.
struct UITestShowcasePersistence: PersistenceProtocol {
    private let wrapped: any PersistenceProtocol

    init(wrapping wrapped: any PersistenceProtocol) {
        self.wrapped = wrapped
    }

    func bootstrap() async throws {
        try await wrapped.bootstrap()
    }

    func latestInProgress() async throws -> SavedGameSummary? {
        try await wrapped.latestInProgress()
    }

    func loadOrCreate(
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> GameSessionSnapshot {
        guard puzzleId == SudokuShowcaseBoard.puzzleId else {
            return try await wrapped.loadOrCreate(puzzleId: puzzleId, mode: mode, difficulty: difficulty)
        }
        return try SudokuShowcaseBoard.snapshot()
    }

    func loadIfExists(
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> GameSessionSnapshot? {
        guard puzzleId == SudokuShowcaseBoard.puzzleId else {
            return try await wrapped.loadIfExists(puzzleId: puzzleId, mode: mode, difficulty: difficulty)
        }
        return try SudokuShowcaseBoard.snapshot()
    }

    func save(
        _ snapshot: GameSessionSnapshot,
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws {
        guard puzzleId != SudokuShowcaseBoard.puzzleId else { return }
        try await wrapped.save(snapshot, puzzleId: puzzleId, mode: mode, difficulty: difficulty)
    }

    func markCompleted(_ summary: SavedGameSummary) async throws {
        guard summary.puzzleId != SudokuShowcaseBoard.puzzleId else { return }
        try await wrapped.markCompleted(summary)
    }

    func deleteAbandoned(recordName: String) async throws {
        try await wrapped.deleteAbandoned(recordName: recordName)
    }

    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> {
        try await wrapped.fetchCompletedDailyIds(for: date)
    }

    func fetchCompletedDailyIdsByDay() async throws -> [String: Set<String>] {
        try await wrapped.fetchCompletedDailyIdsByDay()
    }

    func fetchPersonalRecord(mode: Mode, difficulty: Difficulty) async throws -> PersonalRecord {
        try await wrapped.fetchPersonalRecord(mode: mode, difficulty: difficulty)
    }

    func upsertPersonalRecord(_ record: PersonalRecord) async throws {
        try await wrapped.upsertPersonalRecord(record)
    }

    func recordPuzzleCompletion(
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty,
        elapsedSeconds: Int
    ) async throws {
        try await wrapped.recordPuzzleCompletion(
            puzzleId: puzzleId,
            mode: mode,
            difficulty: difficulty,
            elapsedSeconds: elapsedSeconds
        )
    }
}

#endif

/// Resolves the `PersistenceProtocol` `SudokuAppComposition.Live` wires,
/// wrapping `persistence` in `UITestShowcasePersistence` under
/// `-uitest-route board:showcase` (DEBUG only) so the fixed showcase board
/// never reaches CloudKit. Always defined (mirrors `resolvePersistence`) so
/// `Live.swift` can call it unconditionally without its own `#if DEBUG`.
func resolveShowcasePersistence(_ persistence: any PersistenceProtocol) -> any PersistenceProtocol {
    #if DEBUG
    guard UITestLaunchArg.routeValue() == UITestLaunchArg.showcaseBoardRouteKey else {
        return persistence
    }
    return UITestShowcasePersistence(wrapping: persistence)
    #else
    return persistence
    #endif
}
