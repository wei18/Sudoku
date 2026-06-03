// MinesweeperDailyProvider — thin daily-trio source for the Daily hub (#290).
//
// Mirrors Sudoku's `PuzzleProviderProtocol.fetchDailyTrio(date:)` seam, but
// MS generation is synchronous + pure (no async generator, no CloudKit-backed
// store), so this protocol is a plain `Sendable` value source. The live impl
// wraps the engine's `MinesweeperDaily` static API; injecting a protocol keeps
// the view model testable + mirrors Sudoku's composition shape.

public import MinesweeperEngine
public import Foundation

public protocol MinesweeperDailyProviding: Sendable {
    /// The three daily boards (one per difficulty) for `date`'s UTC day.
    func dailyTrio(date: Date) -> [MinesweeperDailyEntry]
}

/// A single daily board descriptor: stable id + difficulty + the date-seeded
/// seed handed to `.board(difficulty:seed:)`.
public struct MinesweeperDailyEntry: Hashable, Sendable, Identifiable {
    public let puzzleId: String
    public let difficulty: Difficulty
    public let seed: UInt64

    public var id: String { puzzleId }

    public init(puzzleId: String, difficulty: Difficulty, seed: UInt64) {
        self.puzzleId = puzzleId
        self.difficulty = difficulty
        self.seed = seed
    }
}

/// Live provider — derives the trio deterministically from `MinesweeperDaily`.
public struct LiveMinesweeperDailyProvider: MinesweeperDailyProviding {
    public init() {}

    public func dailyTrio(date: Date) -> [MinesweeperDailyEntry] {
        MinesweeperDaily.dailyDifficulties.map { difficulty in
            MinesweeperDailyEntry(
                puzzleId: MinesweeperDaily.puzzleId(date: date, difficulty: difficulty),
                difficulty: difficulty,
                seed: MinesweeperDaily.seed(date: date, difficulty: difficulty)
            )
        }
    }
}
