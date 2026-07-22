// UITestSeededCompletedDailyPersistence — #935 batch 3, DEBUG-only fault
// injection for `PersistenceProtocol`, gated by
// `-uitest-seed-completed-daily` (`GameAppKit.UITestLaunchArg.seedCompletedDaily`).
// Wraps the live persistence and reports today's daily trio as already
// completed so the N12 re-view completion route (docs/navigation-flows.md)
// can be exercised deterministically — completed-daily state lives in
// CloudKit Private DB and cannot be produced by real play on a signed-out/
// offline CI simulator (the near-win boards use no-op persistence and write
// nothing). Every other call delegates to the wrapped live persistence.
// Absent from Release builds via the `#if DEBUG` guard.

internal import Foundation
internal import SudokuEngine
internal import SudokuGameState
internal import SudokuPersistence
internal import Persistence
#if DEBUG
internal import GameAppKit
#endif

#if DEBUG

/// Frozen elapsed/mistake values baked into every seeded completed-daily
/// snapshot — plausible, deterministic, and easy to recognize in logs.
private enum UITestSeededCompletedDailyValues {
    static let elapsedSeconds = 185
    static let mistakeCount = 1
}

/// Wraps a live `PersistenceProtocol` and reports today's daily trio (all
/// three difficulties) as already completed. `loadIfExists` hands back a
/// frozen completed snapshot for any of today's daily puzzleIds, built from
/// the real `Puzzle` the puzzleProvider reverse-derives for that id — the
/// scenario is deterministic but not synthetic garbage. Everything else
/// delegates to `wrapped` unchanged.
struct UITestSeededCompletedDailyPersistence: PersistenceProtocol {
    private let wrapped: any PersistenceProtocol
    private let puzzleProvider: any PuzzleProviderProtocol
    private let dateProvider: @Sendable () -> Date

    init(
        wrapping wrapped: any PersistenceProtocol,
        puzzleProvider: any PuzzleProviderProtocol,
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.wrapped = wrapped
        self.puzzleProvider = puzzleProvider
        self.dateProvider = dateProvider
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
        try await wrapped.loadOrCreate(puzzleId: puzzleId, mode: mode, difficulty: difficulty)
    }

    /// Any of today's three daily puzzleIds resolves to a frozen,
    /// already-completed snapshot instead of hitting CloudKit — this is what
    /// lets `DailyHubViewModel.openCompleted` push `.completion`
    /// deterministically. Practice ids and non-today dailies delegate
    /// unchanged.
    func loadIfExists(
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> GameSessionSnapshot? {
        guard mode == .daily, Self.todaysDailyPuzzleIds(date: dateProvider()).contains(puzzleId) else {
            return try await wrapped.loadIfExists(puzzleId: puzzleId, mode: mode, difficulty: difficulty)
        }
        let puzzle = try await puzzleProvider.puzzle(for: puzzleId)
        return GameSessionSnapshot(
            puzzle: puzzle,
            currentBoard: puzzle.solution,
            status: .completed,
            elapsedSeconds: UITestSeededCompletedDailyValues.elapsedSeconds,
            undoMoves: [],
            redoMoves: [],
            notes: NotesGrid(),
            mistakeCount: UITestSeededCompletedDailyValues.mistakeCount
        )
    }

    func save(
        _ snapshot: GameSessionSnapshot,
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws {
        try await wrapped.save(snapshot, puzzleId: puzzleId, mode: mode, difficulty: difficulty)
    }

    func markCompleted(_ summary: SavedGameSummary) async throws {
        try await wrapped.markCompleted(summary)
    }

    func deleteAbandoned(recordName: String) async throws {
        try await wrapped.deleteAbandoned(recordName: recordName)
    }

    /// Reports today's three daily puzzleIds as completed, unioned with
    /// whatever the wrapped live store genuinely has (best-effort — a
    /// signed-out/offline live store throwing here degrades to "nothing
    /// extra", never blocks the seeded ids).
    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> {
        let seeded = Self.todaysDailyPuzzleIds(date: dateProvider())
        let live = (try? await wrapped.fetchCompletedDailyIds(for: date)) ?? []
        return seeded.union(live)
    }

    /// Same seed-and-union approach as `fetchCompletedDailyIds(for:)`, but
    /// bucketed by UTC day — this is the method `DailyHubViewModel`'s
    /// week-strip window actually reads (`fetchWeekWindow`), so it's what
    /// makes the completed card's checkmark render `true`.
    func fetchCompletedDailyIdsByDay() async throws -> [String: Set<String>] {
        var byDay = (try? await wrapped.fetchCompletedDailyIdsByDay()) ?? [:]
        let today = dateProvider()
        let key = UTCDay.string(from: today)
        byDay[key, default: []].formUnion(Self.todaysDailyPuzzleIds(date: today))
        return byDay
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

    /// Today's three daily puzzleIds — `PuzzleIdentity.daily`'s format,
    /// deterministic from the UTC day + difficulty (no trio fetch needed).
    private static func todaysDailyPuzzleIds(date: Date) -> Set<String> {
        Set([Difficulty.easy, .medium, .hard].map {
            PuzzleIdentity.daily(date: date, difficulty: $0).puzzleId
        })
    }
}

#endif

/// Resolves the `PersistenceProtocol` `live()` wires into `SudokuAppComposition`
/// + `LiveRouteFactory`. Under `-uitest-seed-completed-daily` (DEBUG only),
/// wraps `live` in `UITestSeededCompletedDailyPersistence` so the N12 re-view
/// completion route is reachable without CloudKit. Always defined (mirrors
/// `resolvePuzzleProvider`) so `Live.swift` can call it unconditionally
/// without its own `#if DEBUG`.
func resolvePersistence(
    live: any PersistenceProtocol,
    puzzleProvider: any PuzzleProviderProtocol
) -> any PersistenceProtocol {
    #if DEBUG
    guard ProcessInfo.processInfo.arguments.contains(UITestLaunchArg.seedCompletedDaily) else {
        return live
    }
    return UITestSeededCompletedDailyPersistence(wrapping: live, puzzleProvider: puzzleProvider)
    #else
    return live
    #endif
}
