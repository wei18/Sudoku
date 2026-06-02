// LiveRouteFactory — Minesweeper's concrete `RouteFactory<AppRoute>`.
//
// Mirrors `SudokuKit.LiveRouteFactory` but radically simpler — Standard tier
// has no protocol deps (no PersistenceProtocol, no MonetizationCore, no
// GameCenterClient, no Telemetry). The factory exists for the same shape
// reason: keep `MinesweeperRoot.init` at one argument (the factory) even as
// destination construction grows.
//
// The board destination is wrapped with a "New Game" toolbar Button that
// pops back to the picker (`popToNewGame` → `path.removeAll()`). Wrapping at
// this site (instead of editing `MinesweeperBoardView`) keeps the merged MVP
// file's public API untouched.
//
// `popToNewGame` is the testable extraction of the toolbar action — calling
// `removeAll()` (vs `removeLast()`) is correct for any path depth and safe
// when the path is empty or the binding is nil. Sidebar "New Game" uses the
// same semantics (see `MinesweeperRoot.sidebarItems`).

public import SwiftUI
public import GameShellUI
public import MinesweeperUI

public struct LiveRouteFactory: RouteFactory {
    public typealias Route = AppRoute

    public init() {}

    @MainActor
    public func view(for route: AppRoute, path: Binding<[AppRoute]>?) -> AnyView {
        switch route {
        case .board(let difficulty, let seed):
            return AnyView(
                MinesweeperBoardView(difficulty: difficulty, seed: seed)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("New Game", systemImage: "plus.circle") {
                                // Pop everything off the stack — root content
                                // (NewGameView) becomes visible again so the
                                // user can pick a fresh difficulty + seed.
                                Self.popToNewGame(path: path)
                            }
                            .accessibilityIdentifier("minesweeper.board.newGame")
                        }
                    }
            )
        case .settings:
            return AnyView(SettingsView())
        }
    }

    /// Empties the navigation path so the root content (NewGameView) becomes
    /// visible again. Safe against any path depth, empty path, and nil
    /// binding. Extracted for unit testing — see `LiveRouteFactoryTests`.
    @MainActor
    internal static func popToNewGame(path: Binding<[AppRoute]>?) {
        path?.wrappedValue.removeAll()
    }
}
