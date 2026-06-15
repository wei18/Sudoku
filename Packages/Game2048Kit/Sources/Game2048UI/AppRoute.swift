// AppRoute — Tiles2048's navigation destination enum.
//
// M3: `.board` now carries seed + mode so the game session is deterministic.
//   Classic (practice) mode: a fresh UInt64 seed chosen at navigation time.
//   Daily mode:              Game2048Daily.seed(forDate: .now), derived in
//                            Game2048Root before pushing the route.
//
// M4 will add:
//   case resumeBoard(recordName: String, mode: GameMode)
//
// `Hashable + Sendable` required by SwiftUI `.navigationDestination(for:)`
// + GameShellUI's `RouteFactory`.

public enum AppRoute: Hashable, Sendable {
    /// Launch a new game session with the given seed and mode.
    case board(seed: UInt64, mode: GameMode)
    case settings
}
