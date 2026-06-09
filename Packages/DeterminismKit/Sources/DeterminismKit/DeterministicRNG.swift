// DeterministicRNG — value-type seeded RNG protocol used by both game cores.
//
// Why mutating value type rather than AnyObject:
//   - Bit-identical determinism (Sudoku §How.4.6; Minesweeper daily replay) is
//     easier to reason about with copy-on-pass value semantics — every
//     recursive descent into the generator owns its own RNG snapshot, and
//     mine placement stays bit-identical across devices for a given
//     (difficulty, seed, first-click) tuple.
//   - Avoids reference-cycle / aliasing surprises in nested DFS retries.
//   - Sendable conformance is trivial for value types.
//
// Hoisted into the game-agnostic `DeterminismKit` leaf (#446); previously
// duplicated in `SudokuEngine` and `MinesweeperEngine`.

public protocol DeterministicRNG: Sendable {
    mutating func next() -> UInt64
}

// MARK: - Convenience helpers used by the generators.

extension DeterministicRNG {
    /// Uniformly samples `0..<upperBound` using rejection sampling
    /// (Lemire-style "unbiased ranged random"). For small bounds this is
    /// effectively `next() % upperBound` with a thin rejection band.
    public mutating func nextInt(upperBound: Int) -> Int {
        precondition(upperBound > 0, "upperBound must be > 0")
        let bound = UInt64(upperBound)
        // Reject the top remainder zone to keep the distribution unbiased.
        let threshold = UInt64.max - (UInt64.max % bound)
        while true {
            let sample = next()
            if sample < threshold {
                return Int(sample % bound)
            }
        }
    }

    /// In-place Fisher–Yates shuffle driven by this RNG.
    public mutating func shuffleInPlace<T>(_ array: inout [T]) {
        guard array.count > 1 else { return }
        for index in stride(from: array.count - 1, through: 1, by: -1) {
            let swap = nextInt(upperBound: index + 1)
            if swap != index {
                array.swapAt(index, swap)
            }
        }
    }
}
