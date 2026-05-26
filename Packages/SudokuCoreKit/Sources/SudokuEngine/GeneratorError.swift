// GeneratorError — failure modes for PuzzleGenerator.
//
// `exhausted` is a defect-level event per docs/v1/design.md §How.4.4 / §How.6 — the
// retry budget (N=32) was consumed without producing a valid puzzle.
// `cancelled` is reserved for cooperative cancellation paths added later.

public enum GeneratorError: Error, Sendable, Equatable {
    case exhausted
    case cancelled
}
