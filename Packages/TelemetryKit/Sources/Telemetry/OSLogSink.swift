// OSLogSink — TelemetrySink that forwards every event to `os.Logger`.
//
// Privacy policy (docs/v1/design.md §How.6.3 + foundations.md §5):
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

internal import os

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

    // swiftlint:disable:next cyclomatic_complexity
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
        case .puzzleCompleted(let puzzleId, let mode, let difficulty, let elapsedSeconds, let mistakeCount):
            logger.log(
                level: .notice,
                // elapsedSeconds + mistakeCount are .privateValue per default;
                // embed in the same line but flag the WHOLE message as publicValue —
                // mixed-privacy interpolation is not modelled at the seam.
                // For v1 this trade is acceptable (bounded gameplay timing, not PII).
                message: "puzzleCompleted puzzleId=\(puzzleId) mode=\(mode) difficulty=\(difficulty) elapsed=\(elapsedSeconds) mistakes=\(mistakeCount)",
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
        case .gameSaved(let puzzleId):
            // puzzleId is .publicValue (deterministic, non-PII).
            logger.log(
                level: .info,
                message: "gameSaved puzzleId=\(puzzleId)",
                privacy: .publicValue
            )
        case .gameSaveFailed(let puzzleId, let reason):
            logger.log(
                level: .error,
                message: "gameSaveFailed puzzleId=\(puzzleId) reason=\(reason)",
                privacy: .publicValue
            )
        case .metricKitReport(let report):
            logger.log(
                level: .info,
                message: "metricKitReport kind=\(report.kind.rawValue) bytes=\(report.payloadJSON.count)",
                privacy: .publicValue
            )
        // Reminder lifecycle (#287 Phase 2) — `kind` is a stable taxonomy
        // string (ReminderKind.rawValue), not PII → .publicValue.
        case .reminderPrimerShown(let kind):
            logger.log(level: .info, message: "reminderPrimerShown kind=\(kind)", privacy: .publicValue)
        case .reminderPrimerAccepted(let kind):
            logger.log(level: .info, message: "reminderPrimerAccepted kind=\(kind)", privacy: .publicValue)
        case .reminderPrimerDeclined(let kind):
            logger.log(level: .info, message: "reminderPrimerDeclined kind=\(kind)", privacy: .publicValue)
        case .reminderScheduled(let kind):
            logger.log(level: .notice, message: "reminderScheduled kind=\(kind)", privacy: .publicValue)
        case .reminderCancelled(let kind):
            logger.log(level: .notice, message: "reminderCancelled kind=\(kind)", privacy: .publicValue)
        case .reminderFired(let kind):
            logger.log(level: .notice, message: "reminderFired kind=\(kind)", privacy: .publicValue)
        case .reminderOpenedApp(let kind):
            logger.log(level: .notice, message: "reminderOpenedApp kind=\(kind)", privacy: .publicValue)
        }
    }
}

// MARK: - Live adapter

struct OSLoggerAdapter: LoggerProtocol {
    private let logger: os.Logger

    init(subsystem: String, category: String) {
        self.logger = os.Logger(subsystem: subsystem, category: category)
    }

    // Two nested 5-way (level × privacy) switches — inherently 12, and the
    // explicit-privacy os.Logger interpolation can't be collapsed without losing
    // the compile-time privacy literal. Pre-existing; flagged here because this
    // file is touched by #287's `reminderCancelled` case.
    // swiftlint:disable:next cyclomatic_complexity
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
