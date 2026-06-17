// PracticeSalt — UInt64 entropy source for practice puzzle ids.
//
// Per docs/v1/design.md §How.4.1 末段: salt comes from injected non-persistent system
// entropy. The default closure pulls from `SystemRandomNumberGenerator` (which
// uses arc4random on Apple platforms); tests can inject a deterministic
// closure (e.g. an incrementing counter) for reproducibility.
//
// Practice mode never submits to Game Center (§How.3.1 / §How.7.5), so salt
// quality drives "player experience variety" rather than competitive fairness.

public struct PracticeSalt: Sendable {
    private let source: @Sendable () -> UInt64

    public init(source: @escaping @Sendable () -> UInt64 = { UInt64.random(in: 0...UInt64.max) }) {
        self.source = source
    }

    public func next() -> UInt64 { source() }
}
