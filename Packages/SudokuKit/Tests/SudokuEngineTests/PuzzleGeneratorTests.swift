import Foundation
import Testing
@testable import SudokuEngine

@Suite("PuzzleGenerator")
struct PuzzleGeneratorTests {

    @Test func generateDeterministicSameInputSameOutput() throws {
        let first = try PuzzleGenerator.generate(seed: 0, difficulty: .easy, version: .v1)
        let second = try PuzzleGenerator.generate(seed: 0, difficulty: .easy, version: .v1)
        #expect(first == second)
    }

    @Test func generateDifferentSeedDifferentOutput() throws {
        let zero = try PuzzleGenerator.generate(seed: 0, difficulty: .easy, version: .v1)
        let one = try PuzzleGenerator.generate(seed: 1, difficulty: .easy, version: .v1)
        #expect(zero.clues.encoded() != one.clues.encoded())
    }

    @Test func generateEasyClueCountInRange() throws {
        let puzzle = try PuzzleGenerator.generate(seed: 0, difficulty: .easy, version: .v1)
        let cal = PuzzleCalibrator.calibrate(puzzle.clues)
        #expect((32...50).contains(cal.clueCount))
    }

    @Test func generateMediumClueCountInRange() throws {
        let puzzle = try PuzzleGenerator.generate(seed: 0, difficulty: .medium, version: .v1)
        let cal = PuzzleCalibrator.calibrate(puzzle.clues)
        #expect((28...38).contains(cal.clueCount))
    }

    @Test func generateHardClueCountInRange() throws {
        let puzzle = try PuzzleGenerator.generate(seed: 0, difficulty: .hard, version: .v1)
        let cal = PuzzleCalibrator.calibrate(puzzle.clues)
        #expect((22...32).contains(cal.clueCount))
    }

    @Test func generateEasySolutionIsValid() throws {
        let puzzle = try PuzzleGenerator.generate(seed: 0, difficulty: .easy, version: .v1)
        #expect(puzzle.solution.conflicts().isEmpty)
        #expect(puzzle.solution.isSolved)
    }

    @Test func generateEasyCluesAreSubsetOfSolution() throws {
        let puzzle = try PuzzleGenerator.generate(seed: 0, difficulty: .easy, version: .v1)
        for index in 0..<Board.cellCount {
            let clue = puzzle.clues.cellRaw(at: index)
            let solved = puzzle.solution.cellRaw(at: index)
            if clue != 0 {
                #expect(clue == solved, "clue at \(index) (\(clue)) must match solution (\(solved))")
            }
        }
    }

    @Test func generateEasyPassesUniqueness() throws {
        let puzzle = try PuzzleGenerator.generate(seed: 0, difficulty: .easy, version: .v1)
        let validation = UniquenessValidator.validate(clues: puzzle.clues)
        guard case .unique(let solution) = validation else {
            Issue.record("Expected .unique, got \(validation)")
            return
        }
        // Compare cells only — UniquenessValidator returns a Board whose
        // givenMask reflects the clue subset, while puzzle.solution carries
        // an all-empty givenMask (the solved grid has no "clues").
        #expect(solution.cells == puzzle.solution.cells)
    }

    @Test func generateEasyPassesCalibrator() throws {
        let puzzle = try PuzzleGenerator.generate(seed: 0, difficulty: .easy, version: .v1)
        #expect(PuzzleCalibrator.accepts(puzzle.clues, as: .easy))
    }

    @Test func generateMediumPassesCalibrator() throws {
        let puzzle = try PuzzleGenerator.generate(seed: 0, difficulty: .medium, version: .v1)
        #expect(PuzzleCalibrator.accepts(puzzle.clues, as: .medium))
    }

    @Test func generateHardPassesCalibrator() throws {
        let puzzle = try PuzzleGenerator.generate(seed: 0, difficulty: .hard, version: .v1)
        #expect(PuzzleCalibrator.accepts(puzzle.clues, as: .hard))
    }

    @Test func puzzleRoundtripCodable() throws {
        let puzzle = try PuzzleGenerator.generate(seed: 0, difficulty: .easy, version: .v1)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(puzzle)
        let decoded = try decoder.decode(Puzzle.self, from: data)
        #expect(decoded == puzzle)
    }

    @Test func generateFrozenEasySeed0Snapshot() throws {
        let puzzle = try PuzzleGenerator.generate(seed: 0, difficulty: .easy, version: .v1)
        #expect(puzzle.clues.encoded() == PuzzleGeneratorSnapshots.easySeed0Clues)
        #expect(puzzle.solution.encoded() == PuzzleGeneratorSnapshots.easySeed0Solution)
    }

    @Test func generateFrozenMediumSeed0Snapshot() throws {
        let puzzle = try PuzzleGenerator.generate(seed: 0, difficulty: .medium, version: .v1)
        #expect(puzzle.clues.encoded() == PuzzleGeneratorSnapshots.mediumSeed0Clues)
        #expect(puzzle.solution.encoded() == PuzzleGeneratorSnapshots.mediumSeed0Solution)
    }

    @Test func retryBudgetIs32() {
        #expect(PuzzleGenerator.retryBudget == 32)
    }

    @Test func generatorErrorExhaustedIsDistinct() {
        #expect(GeneratorError.exhausted != GeneratorError.cancelled)
    }

    @Test func generateFrozenHardSeed0Snapshot() throws {
        let puzzle = try PuzzleGenerator.generate(seed: 0, difficulty: .hard, version: .v1)
        #expect(puzzle.clues.encoded() == PuzzleGeneratorSnapshots.hardSeed0Clues)
        #expect(puzzle.solution.encoded() == PuzzleGeneratorSnapshots.hardSeed0Solution)
    }
}
