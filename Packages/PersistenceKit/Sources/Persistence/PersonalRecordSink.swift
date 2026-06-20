// PersonalRecordSink — #578: writes PersonalRecord on completion.
//
// Fires regardless of Game Center auth (PersonalRecord is the durable source
// of truth, independent of GC). Uses the existing facade methods
// `fetchPersonalRecord` + `upsertPersonalRecord` via the pure merge method
// `PersonalRecord.recordingCompletion` — no new PersistenceProtocol methods.

public import Foundation
public import Telemetry
internal import SudokuEngine

/// #578: writes PersonalRecord on completion. Fires regardless of Game Center
/// auth (PersonalRecord is the durable source of truth, independent of GC).
public actor PersonalRecordSink: TelemetrySink {
    private let persistence: any PersistenceProtocol
    private let errorReporter: any ErrorReporter
    private let clock: @Sendable () -> Date

    public init(
        persistence: any PersistenceProtocol,
        errorReporter: any ErrorReporter = NoopErrorReporter(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.persistence = persistence
        self.errorReporter = errorReporter
        self.clock = clock
    }

    public func receive(_ event: TelemetryEvent) async {
        guard case let .puzzleCompleted(puzzleId, mode, difficulty, elapsedSeconds, _) = event else { return }
        do {
            let existing = try await persistence.fetchPersonalRecord(mode: mode, difficulty: difficulty)
            guard let updated = existing.recordingCompletion(
                puzzleId: puzzleId, elapsedSeconds: elapsedSeconds, at: clock()
            ) else { return }
            try await persistence.upsertPersonalRecord(updated)
        } catch {
            await errorReporter.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "PersonalRecordSink"
            )
        }
    }
}
