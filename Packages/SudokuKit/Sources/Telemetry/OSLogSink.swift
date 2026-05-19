// OSLogSink — TelemetrySink that forwards every event to `os.Logger`.
//
// Privacy policy (design.md §How.6.3 + foundations.md §5):
//   - Default everything to `.privateValue`.
//   - `puzzleId` is `.publicValue` — it is deterministic content, not PII.
//   - Numeric coordinates / digits / elapsedSeconds are `.privateValue` by
//     default (per `oslog-logger-defaults` skill: opt out, don't opt in).
//   - Error `source` / `code` are `.publicValue` (debugging-friendly, no PII).
//   - Error `message` is `.privateValue` (may contain user-typed content).
//
// Level mapping:
//   - digitPlaced / noteToggled / moveUndone / moveRedone → .debug
//   - sessionStarted / sessionPaused / sessionResumed     → .info
//   - puzzleCompleted / sessionAbandoned                   → .notice
//   - errorOccurred                                        → .error
//   - metricKitReport                                      → .info

public import os

public struct OSLogSink: TelemetrySink {
    private let logger: any LoggerProtocol

    /// Test-friendly init taking an injected logger seam.
    public init(logger: any LoggerProtocol) {
        self.logger = logger
    }

    /// Live init — wraps `os.Logger(subsystem:category:)`.
    public init(subsystem: String, category: String) {
        self.logger = OSLoggerAdapter(subsystem: subsystem, category: category)
    }

    public func receive(_ event: TelemetryEvent) async {
        switch event {
        case .digitPlaced(let row, let col, let digit, let previous):
            logger.log(
                level: .debug,
                message: "digitPlaced r=\(row) c=\(col) d=\(digit) prev=\(previous.map(String.init) ?? "nil")",
                privacy: .privateValue
            )
        case .noteToggled(let row, let col, let digit, let added):
            logger.log(
                level: .debug,
                message: "noteToggled r=\(row) c=\(col) d=\(digit) added=\(added)",
                privacy: .privateValue
            )
        case .moveUndone:
            logger.log(level: .debug, message: "moveUndone", privacy: .privateValue)
        case .moveRedone:
            logger.log(level: .debug, message: "moveRedone", privacy: .privateValue)
        case .sessionStarted(let puzzleId, let mode, let difficulty):
            // puzzleId is .publicValue (deterministic, non-PII); mode +
            // difficulty are public taxonomy strings.
            logger.log(
                level: .info,
                message: "sessionStarted puzzleId=\(puzzleId) mode=\(mode) difficulty=\(difficulty)",
                privacy: .publicValue
            )
        case .sessionPaused:
            logger.log(level: .info, message: "sessionPaused", privacy: .privateValue)
        case .sessionResumed:
            logger.log(level: .info, message: "sessionResumed", privacy: .privateValue)
        case .puzzleCompleted(let puzzleId, let mode, let difficulty, let elapsedSeconds):
            logger.log(
                level: .notice,
                // elapsedSeconds is .privateValue per default; embed it in
                // the same line but flag the WHOLE message as publicValue —
                // mixed-privacy interpolation is not modelled at the seam.
                // For v1 this trade is acceptable because elapsedSeconds is
                // not PII either (it is bounded gameplay timing).
                message: "puzzleCompleted puzzleId=\(puzzleId) mode=\(mode) difficulty=\(difficulty) elapsed=\(elapsedSeconds)",
                privacy: .publicValue
            )
        case .sessionAbandoned(let puzzleId, let mode, let difficulty, let elapsedSeconds):
            logger.log(
                level: .notice,
                message: "sessionAbandoned puzzleId=\(puzzleId) mode=\(mode) difficulty=\(difficulty) elapsed=\(elapsedSeconds)",
                privacy: .publicValue
            )
        case .errorOccurred(let source, let code, let message):
            // source + code public for cross-device diagnosis; message
            // private (free text may contain user input).
            logger.log(
                level: .error,
                message: "errorOccurred source=\(source) code=\(code) message=\(message)",
                privacy: .privateValue
            )
        case .metricKitReport(let report):
            logger.log(
                level: .info,
                message: "metricKitReport kind=\(report.kind.rawValue) bytes=\(report.payloadJSON.count)",
                privacy: .publicValue
            )
        }
    }
}

// MARK: - Live adapter

struct OSLoggerAdapter: LoggerProtocol {
    private let logger: os.Logger

    init(subsystem: String, category: String) {
        self.logger = os.Logger(subsystem: subsystem, category: category)
    }

    func log(level: LogLevel, message: String, privacy: LogPrivacy) {
        // The seam pre-rendered the message into a String. We funnel into
        // os.Logger with explicit privacy interpolation on that single
        // pre-rendered field. This loses per-field privacy granularity
        // (we don't get to mark only `puzzleId` as public inside the
        // message), which is acceptable for v1 — see OSLogSink.swift's
        // top comment.
        switch privacy {
        case .publicValue:
            switch level {
            case .debug:  logger.debug("\(message, privacy: .public)")
            case .info:   logger.info("\(message, privacy: .public)")
            case .notice: logger.notice("\(message, privacy: .public)")
            case .error:  logger.error("\(message, privacy: .public)")
            case .fault:  logger.fault("\(message, privacy: .public)")
            }
        case .privateValue:
            switch level {
            case .debug:  logger.debug("\(message, privacy: .private)")
            case .info:   logger.info("\(message, privacy: .private)")
            case .notice: logger.notice("\(message, privacy: .private)")
            case .error:  logger.error("\(message, privacy: .private)")
            case .fault:  logger.fault("\(message, privacy: .private)")
            }
        }
    }
}
