// PersonalRecordSink — #578: writes PersonalRecord on completion.
//
// Fires regardless of Game Center auth (PersonalRecord is the durable source
// of truth, independent of GC). Delegates to `recordPuzzleCompletion` (#552)
// which routes through the optimistic retry path on LivePersistence and
// the simple fetch→merge→upsert default on fakes/tests.

public import Telemetry
internal import SudokuEngine

/// #578: writes PersonalRecord on completion. Fires regardless of Game Center
/// auth (PersonalRecord is the durable source of truth, independent of GC).
public actor PersonalRecordSink: TelemetrySink {
    private let persistence: any PersistenceProtocol
    private let errorReporter: any ErrorReporter

    public init(
        persistence: any PersistenceProtocol,
        errorReporter: any ErrorReporter = NoopErrorReporter()
    ) {
        self.persistence = persistence
        self.errorReporter = errorReporter
    }

    public func receive(_ event: TelemetryEvent) async {
        guard case let .puzzleCompleted(puzzleId, mode, difficulty, elapsedSeconds, _) = event else { return }
        do {
            // #552: delegate to recordPuzzleCompletion which routes through
            // the optimistic retry path on LivePersistence.
            try await persistence.recordPuzzleCompletion(
                puzzleId: puzzleId,
                mode: mode,
                difficulty: difficulty,
                elapsedSeconds: elapsedSeconds
            )
        } catch {
            await errorReporter.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "PersonalRecordSink"
            )
        }
    }
}
