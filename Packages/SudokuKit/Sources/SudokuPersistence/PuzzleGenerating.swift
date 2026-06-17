// PuzzleGenerating — internal seam over `SudokuEngine.PuzzleGenerator` that
// PuzzleStore depends on (instead of calling the static directly).
//
// Why a seam:
//   - `FakeGenerator` (SudokuKitTesting) needs to replay canned puzzles + count
//     invocations for cache tests.
//   - Static functions cannot be substituted at the call site without
//     dependency-injecting a thunk anyway, so we may as well give it a name.
//
// `LivePuzzleGenerating` is the only production impl and is the default for
// `PuzzleStore.init`. `FakeGenerator` lives in SudokuKitTesting (test-only).

public import SudokuEngine

public protocol PuzzleGenerating: Sendable {
    func generate(
        seed: UInt64,
        difficulty: Difficulty,
        version: GeneratorVersion
    ) throws -> Puzzle
}

public struct LivePuzzleGenerating: PuzzleGenerating {
    public init() {}

    public func generate(
        seed: UInt64,
        difficulty: Difficulty,
        version: GeneratorVersion
    ) throws -> Puzzle {
        try PuzzleGenerator.generate(seed: seed, difficulty: difficulty, version: version)
    }
}
