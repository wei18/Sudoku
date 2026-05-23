// Puzzle — output of PuzzleGenerator.generate(seed:difficulty:version:).
//
// Pure value type, deterministic content per docs/v1/design.md §How.4.3.

public struct Puzzle: Sendable, Equatable, Hashable, Codable {
    public let clues: Board
    public let solution: Board
    public let difficulty: Difficulty
    public let generatorVersion: GeneratorVersion
    public let seed: UInt64

    public init(
        clues: Board,
        solution: Board,
        difficulty: Difficulty,
        generatorVersion: GeneratorVersion,
        seed: UInt64
    ) {
        self.clues = clues
        self.solution = solution
        self.difficulty = difficulty
        self.generatorVersion = generatorVersion
        self.seed = seed
    }
}
