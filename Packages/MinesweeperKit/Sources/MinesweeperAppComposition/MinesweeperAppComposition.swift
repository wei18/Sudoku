// MinesweeperAppComposition — DI composition root for the Minesweeper app.
//
// Standard tier (2026-06-02) wires only the `RouteFactory<AppRoute>` —
// Sudoku's bag also holds PersistenceProtocol, MonetizationCore, GameCenter,
// Telemetry, and a toast surface; none of those have a Minesweeper product
// definition yet. Follow-up issues will grow this bag as each subsystem is
// designed.
//
// Public surface:
//
//   - `MinesweeperAppComposition.live()` — production bag.
//
// The App target reads `bag.rootView` and hands it to `WindowGroup`. A
// separate `.preview()` factory is intentionally not added until a real
// preview-only stub (no-op telemetry, in-memory persistence, etc.) needs to
// diverge from `.live()`.

public import SwiftUI
public import GameShellUI
public import MinesweeperUI

@MainActor
public struct MinesweeperAppComposition {
    public let routeFactory: any RouteFactory<AppRoute>

    public init(routeFactory: any RouteFactory<AppRoute>) {
        self.routeFactory = routeFactory
    }

    /// Convenience accessor — constructs the top-level `MinesweeperRoot` view
    /// bound to this composition's `routeFactory`. The App target just calls
    /// `composition.rootView` inside its `WindowGroup`.
    public var rootView: some View {
        MinesweeperRoot(routeFactory: routeFactory)
    }
}

// MARK: - Factories

extension MinesweeperAppComposition {

    /// Production wiring. Currently delegates to `LiveRouteFactory()` with
    /// no protocol deps; expands once Persistence / Monetization / Telemetry
    /// land for Minesweeper.
    public static func live() -> MinesweeperAppComposition {
        MinesweeperAppComposition(routeFactory: LiveRouteFactory())
    }
}
