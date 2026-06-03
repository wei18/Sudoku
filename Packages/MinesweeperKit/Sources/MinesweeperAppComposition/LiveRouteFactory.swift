// LiveRouteFactory — Minesweeper's concrete `RouteFactory<AppRoute>`.
//
// Mirrors `SudokuKit.LiveRouteFactory` but slimmer — Standard tier still
// has no Persistence-VM / GameCenter wire. The factory exists for the same
// shape reason: keep `MinesweeperRoot.init` at one argument (the factory)
// even as destination construction grows.
//
// MS monetization wire Phase 3 (2026-06-03): factory now threads
// `MonetizationStateController` through so SettingsView can mount the
// shared `MonetizationUI` Purchases rows.
//
// The board destination is wrapped with a "New Game" toolbar Button that
// pops back to the picker (`popToNewGame` → `path.removeAll()`). Wrapping at
// this site (instead of editing `MinesweeperBoardView`) keeps the merged MVP
// file's public API untouched.

public import SwiftUI
public import GameShellUI
public import MinesweeperUI
public import MonetizationCore
public import MonetizationUI

public struct LiveRouteFactory: RouteFactory {
    public typealias Route = AppRoute

    private let monetizationController: MonetizationStateController?
    // U15 (2026-06-03): threaded into `MinesweeperBoardView` so it can mount
    // a `BannerSlotView` mirror below the grid. Optional so the existing
    // Phase 3 callsite (no monetization) keeps compiling; production wires
    // both, previews pass nil.
    private let adProvider: (any AdProvider)?
    private let adGate: AdGate?

    public init(
        monetizationController: MonetizationStateController? = nil,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil
    ) {
        self.monetizationController = monetizationController
        self.adProvider = adProvider
        self.adGate = adGate
    }

    @MainActor
    public func view(for route: AppRoute, path: Binding<[AppRoute]>?) -> AnyView {
        switch route {
        case .board(let difficulty, let seed):
            return AnyView(
                MinesweeperBoardView(
                    difficulty: difficulty,
                    seed: seed,
                    adProvider: adProvider,
                    adGate: adGate
                )
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
            return AnyView(SettingsView(monetizationController: monetizationController))
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
