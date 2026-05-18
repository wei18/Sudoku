// MonotonicClock — minimal time-source seam for `GameSession.elapsedSeconds`.
//
// DESIGN NOTE:
//
// Swift's stdlib `Clock` protocol is generic over `Instant` (an associated
// type). Wiring `any Clock` through an `actor`'s init is fiddly because
// callers must thread the existential's `Instant` arithmetic too. We only
// need a monotonic, second-resolution wall clock for elapsed-time
// accounting (§How.7.2), so a tiny custom protocol over `TimeInterval`
// keeps the call sites clean and tests trivially synchronous.
//
// `LiveMonotonicClock` is the production implementation (wraps
// `ContinuousClock`). `FakeMonotonicClock` lives in the test target so
// tests can advance time deterministically without `Task.sleep`.

public import Foundation

public protocol MonotonicClock: Sendable {
    /// Seconds since some fixed reference point. Monotonically non-decreasing
    /// across the process lifetime. Resolution: at least 1 second.
    var now: TimeInterval { get }
}

public struct LiveMonotonicClock: MonotonicClock {
    private let base: ContinuousClock = ContinuousClock()
    private let origin: ContinuousClock.Instant

    public init() {
        self.origin = ContinuousClock().now
    }

    public var now: TimeInterval {
        let duration = base.now - origin
        let components = duration.components
        return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) * 1e-18
    }
}
