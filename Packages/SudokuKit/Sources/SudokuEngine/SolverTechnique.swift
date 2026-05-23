// SolverTechnique — the three constraint-propagation techniques the v1
// calibrator recognizes. Aligned with docs/v1/design.md §How.4.4.

public enum SolverTechnique: Sendable, Equatable, CaseIterable {
    case nakedSingle
    case hiddenSingle
    case nakedPair
}

public enum SolverProgress: Sendable, Equatable {
    case changed
    case unchanged
}
