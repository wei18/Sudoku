// LoggerProtocol — testable seam over `os.Logger` (foundations.md §5).
//
// `os.Logger`'s privacy is expressed via interpolation
// (`\(value, privacy: .private)`), which is hard to introspect from tests.
// We therefore project log calls onto a small protocol whose only knobs
// are level / message / privacy. The live adapter (`OSLoggerAdapter`)
// chooses the matching `os.Logger` call site; `FakeLogger` in
// SudokuKitTesting records every invocation for assertions.
//
// `log` is intentionally synchronous — call sites are sprinkled across
// OSLogSink's `receive(_:)` which is already `async`, and forcing every
// sink hop into an `await` would make the seam awkward without payoff.
// The FakeLogger handles its own actor isolation internally via `Task`
// dispatch (see SudokuKitTesting/Telemetry/FakeLogger.swift).

public enum LogLevel: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case debug
    case info
    case notice
    case error
    case fault
}

public enum LogPrivacy: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    /// Default — masked in sysdiagnose / cross-device Console.app.
    case privateValue = "private"
    /// Explicit opt-in — values that are not PII (e.g. puzzleId is a
    /// deterministic string, not personally identifying).
    case publicValue = "public"
}

public protocol LoggerProtocol: Sendable {
    func log(level: LogLevel, message: String, privacy: LogPrivacy)
}
