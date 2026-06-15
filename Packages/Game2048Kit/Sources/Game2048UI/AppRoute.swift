// AppRoute — Tiles2048's navigation destination enum.
//
// M4 adds:
//   - .daily: daily hub (seed derived once per UTC day)
//   - .practice: practice hub
//   - .resumeBoard: restore a persisted in-progress board
//
// `Hashable + Sendable` required by SwiftUI `.navigationDestination(for:)`
// + GameShellUI's `RouteFactory`.

public enum AppRoute: Hashable, Sendable {
    /// Launch a new game session with the given seed and mode.
    case board(seed: UInt64, mode: GameMode)
    /// Navigate to the Daily hub (seed derived once per UTC day).
    case daily
    /// Navigate to the Practice hub.
    case practice
    /// Navigate to Settings.
    case settings
    /// Resume a persisted in-progress board (recordName + mode qualifier).
    /// The route factory mounts `Game2048BoardLoaderView`.
    case resumeBoard(recordName: String, mode: GameMode)
}
