// PuzzleEnvelope — bundles a `Puzzle` (pure math, owned by SudokuEngine)
// with its product-layer `PuzzleIdentity` (docs/v1/design.md §How.4.3).
//
// SudokuEngine deliberately does NOT know about puzzleId / kind — keeping the
// engine pure means the same `Puzzle` value can be re-wrapped for different
// product surfaces in the future (e.g. shared puzzles, replays).

public import SudokuEngine

public struct PuzzleEnvelope: Sendable, Equatable, Hashable, Codable {
    public let puzzle: Puzzle
    public let identity: PuzzleIdentity

    public init(puzzle: Puzzle, identity: PuzzleIdentity) {
        self.puzzle = puzzle
        self.identity = identity
    }
}
