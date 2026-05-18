// DeterministicRNG — value-type RNG protocol used throughout the engine.
//
// Why mutating value type rather than AnyObject:
//   - Bit-identical determinism (§How.4.6) is easier to reason about with
//     copy-on-pass value semantics — every recursive descent into the
//     generator owns its own RNG snapshot.
//   - Avoids reference-cycle / aliasing surprises in nested DFS retries.
//   - Sendable conformance is trivial for value types.

public protocol DeterministicRNG: Sendable {
    mutating func next() -> UInt64
}
