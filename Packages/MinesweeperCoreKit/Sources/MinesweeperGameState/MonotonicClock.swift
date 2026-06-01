// MonotonicClock — second-resolution time seam for elapsed-time accounting.
//
// Mirrors `SudokuCoreKit/GameState/MonotonicClock.swift`. A tiny protocol over
// `TimeInterval` keeps call sites and tests trivially synchronous (avoids the
// `any Clock` existential's `Instant` associated-type plumbing).

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
