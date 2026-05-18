// SplitMix64 — verbatim from `docs/design.md §How.4.2`.
//
// Pure integer ops (add, shift, xor, multiply with overflow-truncating &+ / &*).
// Cross-architecture bit-identical per Phase 0 evidence
// (`meetings/2026-05-17_phase0-gates.md`).

public struct SplitMix64: DeterministicRNG, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed &>> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed &>> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed &>> 31)
    }
}

// MARK: - Convenience helpers used by the generator.

extension DeterministicRNG {
    /// Uniformly samples `0..<upperBound` using rejection sampling
    /// (Lemire-style "unbiased ranged random"). For small bounds this is
    /// effectively `next() % upperBound` with a thin rejection band.
    mutating func nextInt(upperBound: Int) -> Int {
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
    mutating func shuffleInPlace<T>(_ array: inout [T]) {
        guard array.count > 1 else { return }
        for index in stride(from: array.count - 1, through: 1, by: -1) {
            let swap = nextInt(upperBound: index + 1)
            if swap != index {
                array.swapAt(index, swap)
            }
        }
    }
}
