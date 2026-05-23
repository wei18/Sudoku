// PuzzleGenerator — single-retry-loop deterministic generator.
//
// Per docs/v1/design.md §How.4.3:
//   1. Init SplitMix64 from seed.
//   2. Generate a complete solved 9x9 grid via randomized backtracking.
//   3. Mask cells in random order to a difficulty-specific target count,
//      using a propagation-only fast check during removal so we cheaply
//      filter out removals that violate uniqueness. (No per-removal full
//      DFS — that was prohibitively slow for Hard.)
//   4. Verify the resulting board satisfies the final difficulty invariants
//      (uniqueness for all; propagation-only for Easy; branchingFactor <= 2
//      for Medium; clue-count band for all).
//   5. On failure, re-seed with (seed + attemptIndex) and retry, up to N=32.
//   6. Exhausted -> throw GeneratorError.exhausted.
//
// All operations are pure: no Date, no SystemRandomNumberGenerator,
// no Set / Dictionary iteration in decision paths (deterministic linear scans only).

public struct PuzzleGenerator: Sendable {

    /// Retry budget per docs/v1/design.md §How.4.3 (N=32).
    public static let retryBudget: Int = 32

    public init() {}

    /// Generate a Puzzle deterministically. Same `(seed, difficulty, version)` always
    /// returns the bit-identical Puzzle.
    public static func generate(
        seed: UInt64,
        difficulty: Difficulty,
        version: GeneratorVersion
    ) throws -> Puzzle {
        // Reseeding loop preserved verbatim: each attempt gets a fresh
        // SplitMix64(seed: seed + attempt). Per-attempt work is delegated
        // to the RNG-injected seam below (which itself runs a single attempt
        // when called this way — `retryBudget = 1`).
        for attempt in 0..<retryBudget {
            let attemptSeed = seed &+ UInt64(attempt)
            var rng = SplitMix64(seed: attemptSeed)
            if let puzzle = try? generate(
                rng: &rng,
                difficulty: difficulty,
                version: version,
                seedTagForRecord: seed,
                retries: 1
            ) {
                return puzzle
            }
        }
        throw GeneratorError.exhausted
    }

    /// RNG-injected seam. Runs up to `retries` attempts against the provided
    /// RNG (which advances continuously — no internal reseeding). The returned
    /// `Puzzle.seed` carries `seedTagForRecord` verbatim; callers using this
    /// seam directly may pass any tag they like (0 in tests is fine).
    ///
    /// Throws `GeneratorError.exhausted` if no attempt produces a valid puzzle.
    public static func generate<RNG: DeterministicRNG>(
        rng: inout RNG,
        difficulty: Difficulty,
        version: GeneratorVersion,
        seedTagForRecord: UInt64,
        retries: Int = retryBudget
    ) throws -> Puzzle {
        for _ in 0..<retries {
            // 1. Solve a full grid via randomized backtracking.
            var solved = Board()
            guard fillSolved(&solved, &rng) else {
                continue
            }

            // 2. Progressively mask using only the cheap propagation check —
            // a cell can be removed iff propagation from the remaining clues
            // still re-derives the solved value at that cell.
            let masked = progressivelyMask(solved: solved, difficulty: difficulty, rng: &rng)

            // 3. Clue-count gate (cheap: counts non-empty cells).
            let clueCount = masked.cells.reduce(0) { $0 + ($1 == 0 ? 0 : 1) }
            guard clueCountInBand(clueCount, for: difficulty) else {
                continue
            }

            // 4. Uniqueness (mandatory for Medium / Hard; implicitly guaranteed
            // for Easy by the propagation-only removal invariant).
            let validation = UniquenessValidator.validate(clues: masked)
            guard case .unique(let validatedSolution) = validation,
                  validatedSolution.cells == solved.cells else {
                continue
            }

            // 5. Branching-factor cap for Medium (Easy / Hard are implicit / unbounded).
            if difficulty == .medium {
                guard PuzzleCalibrator.accepts(masked, as: .medium) else {
                    continue
                }
            }

            return Puzzle(
                clues: masked,
                solution: solved,
                difficulty: difficulty,
                generatorVersion: version,
                seed: seedTagForRecord
            )
        }
        throw GeneratorError.exhausted
    }

    // MARK: - Solved-grid backtracking

    /// Fill `board` (assumed empty or partially filled) to a complete valid Sudoku
    /// using randomized digit ordering driven by `rng`. Returns true on success.
    private static func fillSolved<RNG: DeterministicRNG>(_ board: inout Board, _ rng: inout RNG) -> Bool {
        let grid = CandidateGrid(board: board)
        var chosenIdx = -1
        var chosenCount = 10
        for index in 0..<Board.cellCount where board.cellRaw(at: index) == 0 {
            let count = CandidateGrid.popcount(grid.masks[index])
            if count == 0 { return false }
            if count < chosenCount {
                chosenCount = count
                chosenIdx = index
                if count == 1 { break }
            }
        }
        if chosenIdx < 0 {
            return true
        }

        var digits = CandidateGrid.digits(in: grid.masks[chosenIdx])
        rng.shuffleInPlace(&digits)
        for digit in digits {
            board.setCellRaw(UInt8(digit), at: chosenIdx)
            if fillSolved(&board, &rng) {
                return true
            }
            board.setCellRaw(0, at: chosenIdx)
        }
        return false
    }

    // MARK: - Progressive masking (propagation-only invariant)

    /// Lower bound of the difficulty's accepted clue-count band. Removal stops
    /// once the board reaches this many clues.
    private static func clueFloor(for difficulty: Difficulty) -> Int {
        // Floors sit inside the §How.4.4 accepted bands (`PuzzleCalibrator`).
        switch difficulty {
        case .easy: return 42   // band [32, 50]
        case .medium: return 32 // band [28, 38]
        case .hard: return 26   // band [22, 32]
        }
    }

    private static func clueCountInBand(_ count: Int, for difficulty: Difficulty) -> Bool {
        switch difficulty {
        case .easy: return (32...50).contains(count)
        case .medium: return (28...38).contains(count)
        case .hard: return (22...32).contains(count)
        }
    }

    /// Iterate cells in random order; tentatively clear each cell; keep the
    /// removal only if propagation alone still re-derives the original value.
    ///
    /// This is intentionally a *propagation-only* check — it guarantees the
    /// remaining clue set still uniquely determines the solved grid (via a
    /// strict subset of the techniques in §How.4.4), without paying the cost
    /// of a full DFS uniqueness check at every step. Per-difficulty final
    /// validation runs once at the call site.
    private static func progressivelyMask<RNG: DeterministicRNG>(
        solved: Board,
        difficulty: Difficulty,
        rng: inout RNG
    ) -> Board {
        var indices: [Int] = Array(0..<Board.cellCount)
        rng.shuffleInPlace(&indices)
        var work = boardWithGivenMaskReset(solved)
        let floor = clueFloor(for: difficulty)
        var remainingClues = Board.cellCount

        for cellIdx in indices {
            if remainingClues <= floor { break }
            let saved = work.cellRaw(at: cellIdx)
            if saved == 0 { continue }
            work.setCellRaw(0, at: cellIdx)
            if propagationStillRederives(board: work, solved: solved) {
                remainingClues -= 1
            } else {
                work.setCellRaw(saved, at: cellIdx)
            }
        }
        return boardWithGivenMaskReset(work)
    }

    /// Cheap check: does propagation from the partially-clued `board`
    /// re-derive the full `solved` grid?
    ///
    /// Implementation note: uses a hand-rolled fixed-point loop that detects
    /// "no board change" rather than relying on `Solver.propagate` — the
    /// shared `Solver.applyNakedPair` updates an internal candidate grid that
    /// is discarded between iterations, so its "changed" flag can stay
    /// `true` even when no board cell was filled, producing a non-terminating
    /// loop. We only need naked-single + hidden-single coverage here anyway
    /// (Easy puzzles per §How.4.4 must be solvable by propagation alone, and
    /// our removal invariant for Medium / Hard is the cheap-side fast path).
    private static func propagationStillRederives(board: Board, solved: Board) -> Bool {
        var work = board
        let solver = Solver()
        while true {
            let before = work.cells
            _ = solver.applyOnce(.nakedSingle, to: &work)
            _ = solver.applyOnce(.hiddenSingle, to: &work)
            if work.cells == before { break }
        }
        return work.cells == solved.cells
    }

    /// Reconstruct a Board via Board(clues:) so that givenMask matches the
    /// current cell contents (every non-empty cell becomes a given).
    private static func boardWithGivenMaskReset(_ board: Board) -> Board {
        var chars: [Character] = []
        chars.reserveCapacity(Board.cellCount)
        for index in 0..<Board.cellCount {
            let digit = board.cellRaw(at: index)
            if digit == 0 {
                chars.append(".")
            } else {
                chars.append(Character(UnicodeScalar(UInt8(ascii: "0") + digit)))
            }
        }
        // swiftlint:disable:next force_try
        return try! Board(clues: String(chars))
    }
}
