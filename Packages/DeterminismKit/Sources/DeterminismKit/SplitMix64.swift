// SplitMix64 — verbatim from `docs/v1/design.md §How.4.2`.
//
// Pure integer ops (add, shift, xor, multiply with overflow-truncating &+ / &*).
// Cross-architecture bit-identical per Phase 0 evidence
// (`meetings/2026-05-17_phase0-gates.md`). Drives Sudoku puzzle generation and
// Minesweeper mine placement — the same constants, single source of truth (#446).

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
