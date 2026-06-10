// ErrorReporter — unified funnel for swallowed errors (issue #67 / M10).
//
// Replaces the previous `try?` swallowing pattern. Every catch site at a
// module boundary calls `await reporter.report(.bucket, underlying: error,
// source: "Module.method")`. The Live impl fans the report through
// `Telemetry.observe(.errorOccurred(source:code:message:))` — joining the
// existing fan-out so OSLog / future trackers receive it. (#459: the former
// recent-reports ring buffer + `recent()` were removed — speculative API
// with no production consumer; reintroduce alongside a real debug surface.)
//
// Sendable contract: protocol + every impl Sendable (`actor` for Live and
// Fake; `struct` for Noop). All callers from `@MainActor` view models
// hop into the actor through `await`.

public import Foundation

/// One recorded report, suitable for diagnostic surfaces. `underlyingDescription`
/// is captured eagerly (`String(describing: error)` at report time) so no
/// heterogeneous `Error` existential is retained across actor hops — keeps
/// `FakeErrorReporter.received` (its remaining consumer) cheaply Sendable.
public struct ErrorReport: Sendable, Equatable, Hashable {
    public let error: UserFacingError
    public let source: String
    public let underlyingDescription: String
    public let timestamp: Date

    public init(
        error: UserFacingError,
        source: String,
        underlyingDescription: String,
        timestamp: Date
    ) {
        self.error = error
        self.source = source
        self.underlyingDescription = underlyingDescription
        self.timestamp = timestamp
    }
}

public protocol ErrorReporter: Sendable {
    /// Routes the error into the unified funnel. `underlying` is preserved
    /// for engineering observability (OSLog) but is not surfaced to the
    /// user — UI consumes the `UserFacingError` case only.
    func report(
        _ error: UserFacingError,
        underlying: any Error,
        source: String
    ) async
}

/// Live impl — fans every report through the injected `Telemetry` actor.
public actor LiveErrorReporter: ErrorReporter {
    private let telemetry: Telemetry

    public init(telemetry: Telemetry) {
        self.telemetry = telemetry
    }

    public func report(
        _ error: UserFacingError,
        underlying: any Error,
        source: String
    ) async {
        await telemetry.observe(
            .errorOccurred(
                source: source,
                code: error.rawCode,
                message: String(describing: underlying)
            )
        )
    }
}

/// Fake impl for tests — records every report so test cases can assert
/// that the expected funnel call happened. Lives alongside `LiveErrorReporter`
/// (not in `SudokuKitTesting`) because the `ErrorReporter` protocol lives
/// here and SudokuKitTesting is below AppComposition in the dep graph.
public actor FakeErrorReporter: ErrorReporter {
    public private(set) var received: [ErrorReport] = []
    private let clock: @Sendable () -> Date

    public init(clock: @escaping @Sendable () -> Date = { Date() }) {
        self.clock = clock
    }

    public func report(
        _ error: UserFacingError,
        underlying: any Error,
        source: String
    ) async {
        received.append(
            ErrorReport(
                error: error,
                source: source,
                underlyingDescription: String(describing: underlying),
                timestamp: clock()
            )
        )
    }
}

/// No-op impl for `.preview()` factories — Preview / placeholder hosts that
/// must not invoke `Telemetry` (often the Telemetry sinks list is empty in
/// preview anyway). Discarding the report keeps SwiftUI Previews zero-IO.
public struct NoopErrorReporter: ErrorReporter {
    public init() {}

    public func report(
        _ error: UserFacingError,
        underlying: any Error,
        source: String
    ) async {
        // Intentionally empty.
    }
}
