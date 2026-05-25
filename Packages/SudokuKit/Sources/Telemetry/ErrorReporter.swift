// ErrorReporter — unified funnel for swallowed errors (issue #67 / M10).
//
// Replaces the previous `try?` swallowing pattern. Every catch site at a
// module boundary calls `await reporter.report(.bucket, underlying: error,
// source: "Module.method")`. The Live impl fans the report through:
//   1. `Telemetry.observe(.errorOccurred(source:code:message:))` — joins
//      the existing fan-out so OSLog / future trackers receive it.
//   2. An in-memory ring buffer of the most recent 20 reports for future
//      debug surfaces (shake-to-view, settings diagnostics).
//
// Sendable contract: protocol + every impl Sendable (`actor` for Live and
// Fake; `struct` for Noop). All callers from `@MainActor` view models
// hop into the actor through `await`.

public import Foundation

/// One recorded report, suitable for diagnostic surfaces. `underlyingDescription`
/// is captured eagerly (the Live impl maps `String(describing: error)` at
/// report time) so the actor does not need to retain heterogeneous `Error`
/// existentials across actor hops — keeps the buffer cheaply Sendable.
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

/// Live impl — fans every report through the injected `Telemetry` actor
/// and retains a bounded ring buffer of recent reports.
public actor LiveErrorReporter: ErrorReporter {
    /// Issue #67 acceptance: "in-memory recent-errors buffer (bounded ~20)".
    public static let bufferCapacity = 20

    private let telemetry: Telemetry
    private let clock: @Sendable () -> Date
    private var buffer: [ErrorReport] = []

    public init(
        telemetry: Telemetry,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.telemetry = telemetry
        self.clock = clock
    }

    public func report(
        _ error: UserFacingError,
        underlying: any Error,
        source: String
    ) async {
        let description = String(describing: underlying)
        let report = ErrorReport(
            error: error,
            source: source,
            underlyingDescription: description,
            timestamp: clock()
        )
        appendBounded(report)
        await telemetry.observe(
            .errorOccurred(
                source: source,
                code: error.rawCode,
                message: description
            )
        )
    }

    /// Snapshot of the most recent reports (oldest first). Exposed for
    /// future debug surfaces; tests use `FakeErrorReporter` instead.
    public func recent() -> [ErrorReport] {
        buffer
    }

    private func appendBounded(_ report: ErrorReport) {
        buffer.append(report)
        if buffer.count > Self.bufferCapacity {
            buffer.removeFirst(buffer.count - Self.bufferCapacity)
        }
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
