// MinesweeperAppComposition — DI composition root for the Minesweeper app.
//
// Standard tier (2026-06-02) wires:
//   - `RouteFactory<AppRoute>` — destination construction.
//   - `Telemetry` — fan-out facade (OSLog + NoOp tracking in `.live()`).
//   - `ErrorReporter` — unified swallowed-error funnel.
//
// Sudoku's bag additionally holds PersistenceProtocol, MonetizationCore,
// GameCenter, monetization controllers, and a toast surface; none of those
// have a Minesweeper product definition yet. Follow-up issues will grow this
// bag as each subsystem is designed.
//
// Phase 2 scope (parity-audit telemetry wire): the seam exists on the bag,
// but no MinesweeperUI view consumes it yet. View-level adoption (e.g.
// GameViewModel emitting `.errorOccurred`) lands in a follow-up.
//
// Public surface:
//
//   - `MinesweeperAppComposition.live()`    — production bag (Live.swift).
//   - `MinesweeperAppComposition.preview()` — Preview / test fakes (Live.swift).
//
// The App target reads `bag.rootView` and hands it to `WindowGroup`.

public import SwiftUI
public import GameShellUI
public import MinesweeperUI
public import Telemetry

@MainActor
public struct MinesweeperAppComposition {
    public let routeFactory: any RouteFactory<AppRoute>
    public let telemetry: Telemetry
    public let errorReporter: any ErrorReporter

    public init(
        routeFactory: any RouteFactory<AppRoute>,
        telemetry: Telemetry,
        errorReporter: any ErrorReporter
    ) {
        self.routeFactory = routeFactory
        self.telemetry = telemetry
        self.errorReporter = errorReporter
    }

    /// Convenience accessor — constructs the top-level `MinesweeperRoot` view
    /// bound to this composition's `routeFactory`. The App target just calls
    /// `composition.rootView` inside its `WindowGroup`.
    public var rootView: some View {
        MinesweeperRoot(routeFactory: routeFactory)
    }
}
