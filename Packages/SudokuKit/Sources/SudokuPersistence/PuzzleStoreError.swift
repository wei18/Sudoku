// PuzzleStoreError — failure modes that surface above the PuzzleStore actor.
//
// `generatorFailed` carries the underlying `GeneratorError` description as
// `String` (not the enum) so callers / Telemetry can log the case without
// re-importing SudokuEngine — and so v2 can swap the engine without touching
// downstream switch sites.

public enum PuzzleStoreError: Error, Sendable, Equatable {
    /// `puzzleId` did not match either the daily or practice shape.
    case malformedPuzzleId(String)
    /// `puzzleId` parsed but the difficulty token is not in
    /// `Difficulty.allCases.map(\.rawValue)`.
    case unknownDifficulty(String)
    /// Underlying `PuzzleGenerator` exhausted its retry budget. The string is
    /// the underlying error's `String(describing:)` (intentionally loose).
    case generatorFailed(underlying: String)
}
