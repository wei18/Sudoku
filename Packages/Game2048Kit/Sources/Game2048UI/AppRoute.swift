// AppRoute — Tiles2048's navigation destination enum.
//
// SDD-004 Milestone 2: skeleton shell. Only `.board` is declared as a
// placeholder so the RouteFactory stub compiles. Real board parameters
// (seed, mode — Classic vs. Daily) will be added in Milestone 3 when
// Game2048CoreKit is wired into the UI layer.
//
// Milestone 3 will expand this to mirror MinesweeperKit/AppRoute.swift:
//   case board(seed: UInt64, mode: GameMode)
//   case daily
//   case practice
//   case settings
//   case completion(mode: GameMode)
//   case resumeBoard(recordName: String, mode: GameMode)
//
// `Hashable + Sendable` is the minimum SwiftUI's `.navigationDestination(for:)`
// + GameShellUI's `RouteFactory` require.

public enum AppRoute: Hashable, Sendable {
    // Placeholder board route — parameters (seed, mode) land in M3 once
    // Game2048CoreKit's `Game2048Engine` + `Game2048GameState` are wired.
    case board
    case daily
    case practice
    case settings
}
