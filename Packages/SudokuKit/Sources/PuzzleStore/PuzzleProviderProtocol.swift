// PuzzleProviderProtocol — design.md §How.5.1.
//
// The UI layer talks only to this protocol; `PuzzleStore` (this module) is the
// production impl, `FakePuzzleProvider` (in SudokuKitTesting, future step) is
// the test impl. Persistence depends on `puzzle(for:)` to lazy-reload a puzzle
// from a stored `puzzleId` without storing the full Puzzle blob in CloudKit.

public import Foundation
public import SudokuEngine

public protocol PuzzleProviderProtocol: Sendable {
    /// Today's three puzzles (one per difficulty). Always returned in
    /// `[easy, medium, hard]` order so callers may rely on positional access.
    func fetchDailyTrio(date: Date) async throws -> [PuzzleEnvelope]

    /// Pull one practice puzzle of the requested difficulty. Each call yields
    /// a freshly-salted puzzle (no caching).
    func fetchPracticePool(difficulty: Difficulty) async throws -> PuzzleEnvelope

    /// Reverse lookup used by `Persistence.loadOrCreate`: given a puzzleId
    /// previously emitted by this provider, re-derive the `Puzzle`.
    func puzzle(for puzzleId: String) async throws -> Puzzle
}
