import Testing
@testable import SudokuEngine

@Suite("PuzzleGenerator exhaustion via injected RNG")
struct PuzzleGeneratorExhaustionTests {

    @Test func generateThrowsExhaustedWhenRetryBudgetIsZero() {
        // Seam exhaustion semantics: with `retries: 0`, no attempt runs and
        // the generator must throw `.exhausted` immediately. Proves the
        // retry-budget plumbing is honored by the seam (rather than e.g.
        // silently running one attempt).
        var rng = SplitMix64(seed: 0)
        #expect(throws: GeneratorError.exhausted) {
            _ = try PuzzleGenerator.generate(
                rng: &rng,
                difficulty: .hard,
                version: .v1,
                seedTagForRecord: 0,
                retries: 0
            )
        }
    }

    @Test func generateIsDeterministicWithInjectedRNG() throws {
        // SplitMix64 with the same seed must produce identical Puzzle output
        // through the new seam — proves the seam itself is deterministic.
        var rngA = SplitMix64(seed: 42)
        var rngB = SplitMix64(seed: 42)
        let puzzleA = try PuzzleGenerator.generate(
            rng: &rngA,
            difficulty: .easy,
            version: .v1,
            seedTagForRecord: 42
        )
        let puzzleB = try PuzzleGenerator.generate(
            rng: &rngB,
            difficulty: .easy,
            version: .v1,
            seedTagForRecord: 42
        )
        #expect(puzzleA == puzzleB)
    }

    @Test func seedTagAppearsInRecord() throws {
        var rng = SplitMix64(seed: 7)
        let puzzle = try PuzzleGenerator.generate(
            rng: &rng,
            difficulty: .easy,
            version: .v1,
            seedTagForRecord: 999
        )
        #expect(puzzle.seed == 999)
    }

    @Test func existingSeedAPIStillMatchesFrozenSnapshots() throws {
        // The seed-flavored API must continue to produce the bit-identical
        // Puzzle it always has — i.e., delegating through the seam did not
        // change the deterministic output.
        let puzzle = try PuzzleGenerator.generate(seed: 0, difficulty: .easy, version: .v1)
        #expect(puzzle.clues.encoded() == PuzzleGeneratorSnapshots.easySeed0Clues)
        #expect(puzzle.solution.encoded() == PuzzleGeneratorSnapshots.easySeed0Solution)
        #expect(puzzle.seed == 0)
    }
}
