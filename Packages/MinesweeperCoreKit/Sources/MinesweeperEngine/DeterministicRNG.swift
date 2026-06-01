// DeterministicRNG — value-type seeded RNG protocol.
//
// Mirrors `SudokuCoreKit/Sources/SudokuEngine/DeterministicRNG.swift`. Pure
// value semantics keep mine placement bit-identical across devices for a
// given (difficulty, seed, first-click) tuple, which is what makes daily
// puzzles replayable.

public protocol DeterministicRNG: Sendable {
    mutating func next() -> UInt64
}

extension DeterministicRNG {
    /// Uniformly samples `0..<upperBound` using rejection sampling.
    mutating func nextInt(upperBound: Int) -> Int {
        precondition(upperBound > 0, "upperBound must be > 0")
        let bound = UInt64(upperBound)
        let threshold = UInt64.max - (UInt64.max % bound)
        while true {
            let sample = next()
            if sample < threshold {
                return Int(sample % bound)
            }
        }
    }
}
