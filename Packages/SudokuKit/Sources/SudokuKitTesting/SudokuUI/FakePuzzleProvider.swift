// FakePuzzleProvider — scripted `PuzzleProviderProtocol` for SudokuUI tests.
//
// Default: returns a deterministic Latin-square fixture per difficulty
// (sourced from `PuzzleFixtures`). Tests can override responses via
// `setDailyTrioResult` / `setPracticeResult`.

public import Foundation
public import PuzzleStore
public import SudokuEngine

public actor FakePuzzleProvider: PuzzleProviderProtocol {

    public enum Operation: Sendable, Equatable, Hashable {
        case fetchDailyTrio(date: Date)
        case fetchPracticePool(difficulty: Difficulty)
        case puzzle(for: String)
    }

    public private(set) var operations: [Operation] = []

    public var dailyTrioResult: Result<[PuzzleEnvelope], PuzzleStoreError>
    public var practiceResult: Result<PuzzleEnvelope, PuzzleStoreError>
    /// Optional delay (in nanoseconds) applied to every fetch so tests can
    /// exercise loading-state thresholds.
    public var artificialDelayNanos: UInt64 = 0

    public init(
        dailyTrioResult: Result<[PuzzleEnvelope], PuzzleStoreError>? = nil,
        practiceResult: Result<PuzzleEnvelope, PuzzleStoreError>? = nil
    ) {
        self.dailyTrioResult = dailyTrioResult ?? .success(Self.defaultDailyTrio(date: Date(timeIntervalSince1970: 0)))
        self.practiceResult = practiceResult ?? .success(Self.defaultPracticeEnvelope())
    }

    public func setDailyTrioResult(_ result: Result<[PuzzleEnvelope], PuzzleStoreError>) {
        self.dailyTrioResult = result
    }

    public func setPracticeResult(_ result: Result<PuzzleEnvelope, PuzzleStoreError>) {
        self.practiceResult = result
    }

    public func setArtificialDelay(nanos: UInt64) {
        self.artificialDelayNanos = nanos
    }

    public func fetchDailyTrio(date: Date) async throws -> [PuzzleEnvelope] {
        operations.append(.fetchDailyTrio(date: date))
        await maybeDelay()
        return try dailyTrioResult.get()
    }

    public func fetchPracticePool(difficulty: Difficulty) async throws -> PuzzleEnvelope {
        operations.append(.fetchPracticePool(difficulty: difficulty))
        await maybeDelay()
        return try practiceResult.get()
    }

    public func puzzle(for puzzleId: String) async throws -> Puzzle {
        operations.append(.puzzle(for: puzzleId))
        return Self.defaultPuzzle(difficulty: .easy, seed: 0)
    }

    public func resetOperations() {
        operations.removeAll()
    }

    private func maybeDelay() async {
        if artificialDelayNanos > 0 {
            // try?: test-fixture Task.sleep cancellation — not an error path.
            try? await Task.sleep(nanoseconds: artificialDelayNanos)
        }
    }

    // MARK: - Default fixtures

    public static func defaultDailyTrio(date: Date) -> [PuzzleEnvelope] {
        Difficulty.allCases.enumerated().map { index, difficulty in
            PuzzleEnvelope(
                puzzle: defaultPuzzle(difficulty: difficulty, seed: UInt64(index + 1)),
                identity: PuzzleIdentity.daily(date: date, difficulty: difficulty)
            )
        }
    }

    public static func defaultPracticeEnvelope() -> PuzzleEnvelope {
        PuzzleEnvelope(
            puzzle: defaultPuzzle(difficulty: .medium, seed: 0xCAFE_BABE),
            identity: PuzzleIdentity.practice(salt: 0xCAFE_BABE, difficulty: .medium)
        )
    }

    public static func defaultPuzzle(difficulty: Difficulty, seed: UInt64) -> Puzzle {
        let base = PuzzleFixtures.latinSquarePuzzle()
        return Puzzle(
            clues: base.clues,
            solution: base.solution,
            difficulty: difficulty,
            generatorVersion: .v1,
            seed: seed
        )
    }
}
