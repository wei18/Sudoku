// Live composition — concrete impls for production. design.md §How.1.
//
// Wires:
//   - LiveGameCenterClient(authDriver: GKAuthDriver())
//   - LivePersistence(...) bound to a PuzzleStore puzzle loader
//   - PuzzleStore() — default LivePuzzleGenerating
//   - Telemetry(sinks: [OSLogSink, NoOpTrackingSink, MetricKitSink])

internal import Foundation
internal import GameCenterClient
internal import Persistence
internal import PuzzleStore
internal import SudokuUI
internal import Telemetry

extension AppComposition {

    public static func live() -> AppComposition {
        // Telemetry fan-out: OSLog + NoOp tracking. MetricKit projects its
        // diagnostic payloads BACK INTO this same Telemetry instance via the
        // process-wide retained sink below.
        let telemetry = Telemetry(sinks: [
            OSLogSink(subsystem: "com.wei18.sudoku", category: "Telemetry"),
            NoOpTrackingSink()
        ])
        LiveMetricKitRetainer.install(downstream: telemetry)

        // PuzzleStore (default generator, v1 version).
        let puzzleStore = PuzzleStore()

        // Persistence facade. The puzzle loader closure routes through the
        // same PuzzleStore so SavedGameStore can re-derive a Puzzle from a
        // stored puzzleId (no Puzzle blob in CloudKit).
        let persistence = LivePersistence(
            telemetry: telemetry,
            puzzleLoader: { puzzleId in
                try await puzzleStore.puzzle(for: puzzleId)
            }
        )

        // Game Center client.
        let gameCenter = LiveGameCenterClient(authDriver: GKAuthDriver())

        let rootViewModel = RootViewModel(
            gameCenter: gameCenter,
            persistence: persistence
        )

        return AppComposition(
            rootViewModel: rootViewModel
        )
    }

}

/// Process-wide retainer for `MetricKitSink` — MXMetricManager's subscriber
/// list holds a weak reference, so we must keep the sink alive ourselves
/// for the lifetime of the App. Installation is idempotent.
private enum LiveMetricKitRetainer {
    nonisolated(unsafe) private static var sink: MetricKitSink?
    private static let lock = NSLock()

    static func install(downstream: Telemetry) {
        lock.lock()
        defer { lock.unlock() }
        guard sink == nil else { return }
        let metricSink = MetricKitSink(downstream: downstream)
        // Skip system registration in test environments — MXMetricManager
        // is unavailable outside a properly entitled app bundle and would
        // crash the test process. Detection: swift-testing / XCTest sets
        // `XCTestConfigurationFilePath`.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            metricSink.startReceivingSystemReports()
        }
        sink = metricSink
    }
}
