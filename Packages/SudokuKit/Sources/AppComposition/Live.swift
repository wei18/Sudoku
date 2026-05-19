// Live composition — concrete impls for production. design.md §How.1.
//
// Wires:
//   - LiveGameCenterClient(authDriver: GKAuthDriver())
//   - LivePersistence(...) bound to a PuzzleStore puzzle loader
//   - PuzzleStore() — default LivePuzzleGenerating
//   - Telemetry(sinks: [OSLogSink, NoOpTrackingSink, MetricKitSink])
//
// The GameViewModel factory is `async throws` because it must `await
// persistence.loadOrCreate(...)` to seed the live `GameSession` before
// constructing the VM (Phase 8 Part 2 forecast).

internal import Foundation
internal import GameCenterClient
internal import GameState
internal import Persistence
internal import PuzzleStore
internal import SudokuEngine
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
            rootViewModel: rootViewModel,
            homeViewModelFactory: { HomeViewModel() },
            dailyHubViewModelFactory: {
                DailyHubViewModel(provider: puzzleStore, persistence: persistence)
            },
            practiceHubViewModelFactory: {
                PracticeHubViewModel(provider: puzzleStore)
            },
            gameViewModelFactory: { envelope in
                // Async factory: load (or seed) the snapshot from Persistence
                // FIRST, then build a live GameSession + GameViewModel.
                let identity = envelope.identity
                let snapshot = try await persistence.loadOrCreate(
                    puzzleId: identity.puzzleId,
                    mode: identity.kind.rawValue,
                    difficulty: identity.difficulty
                )
                let adapter = GameStateTelemetryAdapter(
                    telemetry: telemetry,
                    puzzleId: identity.puzzleId,
                    mode: identity.kind.rawValue,
                    difficulty: identity.difficulty
                )
                let session = await GameSession.restore(
                    from: snapshot,
                    telemetry: adapter
                )
                return await MainActor.run {
                    GameViewModel(
                        identity: identity,
                        session: session,
                        initialBoard: snapshot.currentBoard,
                        initialNotes: snapshot.notes,
                        initialStatus: snapshot.status,
                        initialElapsedSeconds: snapshot.elapsedSeconds,
                        persistence: persistence
                    )
                }
            },
            completionViewModelFactory: { puzzleId, elapsedSeconds in
                // Map difficulty out of puzzleId to pick the right leaderboard.
                let leaderboardId = Self.leaderboardId(for: puzzleId)
                return CompletionViewModel(
                    puzzleId: puzzleId,
                    elapsedSeconds: elapsedSeconds,
                    leaderboardId: leaderboardId,
                    gameCenter: gameCenter
                )
            },
            leaderboardViewModelFactory: { leaderboardId in
                LeaderboardViewModel(
                    leaderboardId: leaderboardId,
                    gameCenter: gameCenter
                )
            },
            settingsViewModelFactory: {
                SettingsViewModel(persistence: persistence)
            }
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

extension AppComposition {
    /// Map a daily-puzzleId to its leaderboard. Practice puzzles return the
    /// difficulty-matched daily leaderboard as a fallback — practice scores
    /// are never submitted (§How.3.1) so this is informational only.
    fileprivate static func leaderboardId(for puzzleId: String) -> String {
        if puzzleId.hasSuffix("-hard") {
            return LeaderboardIDs.id(for: .dailyHard)
        }
        if puzzleId.hasSuffix("-medium") {
            return LeaderboardIDs.id(for: .dailyMedium)
        }
        return LeaderboardIDs.id(for: .dailyEasy)
    }
}
