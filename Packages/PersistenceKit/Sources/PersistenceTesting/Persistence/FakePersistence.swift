// FakePersistence — zero-IO `PersistenceProtocol` conformer for Previews/tests.
//
// Lives in the shared `PersistenceTesting` target so any app (Sudoku,
// Minesweeper) can wire a CloudKit-free persistence into its Preview / test
// composition without instantiating `LivePersistence` (whose first call traps
// on a real private-DB gateway). No CloudKit, no IO.
//
// Sudoku's `SudokuKitTesting.FakePersistence` predates this and adds scripted
// operation-tracking for SudokuUI VM call-shape assertions; it is intentionally
// left in place. This type is the minimal shared seam — it tracks nothing and
// returns empty defaults, which is all a zero-IO Preview/composition needs.
//
// This type does not override `loadIfExists` — a re-view test needing the
// #830 nil-vs-throw tri-state should reach for `SudokuKitTesting.FakePersistence`
// instead; calling `loadIfExists` here hits the loud-throw default (#834).

public import Foundation
public import SudokuGameState
public import Persistence
public import SudokuEngine

public actor FakePersistence: PersistenceProtocol {

    public init() {}

    public func bootstrap() async throws {}

    public func latestInProgress() async throws -> SavedGameSummary? { nil }

    public func loadOrCreate(
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> GameSessionSnapshot {
        // Default raises so an accidental load is loud — Preview/composition
        // shape coverage never hits this path.
        throw PersistenceError.zoneNotProvisioned
    }

    public func save(
        _ snapshot: GameSessionSnapshot,
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws {}

    public func markCompleted(_ summary: SavedGameSummary) async throws {}

    public func deleteAbandoned(recordName: String) async throws {}

    public func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> { [] }

    public func fetchCompletedDailyIdsByDay() async throws -> [String: Set<String>] { [:] }

    public func fetchPersonalRecord(
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> PersonalRecord {
        PersonalRecord(
            recordName: "",
            mode: .daily,
            difficulty: .easy,
            bestTimeSeconds: nil,
            totalTimeSeconds: 0,
            completedCount: 0,
            lastUpdatedAt: Date(timeIntervalSince1970: 0),
            completedPuzzleIds: []
        )
    }

    public func upsertPersonalRecord(_ record: PersonalRecord) async throws {}
}
