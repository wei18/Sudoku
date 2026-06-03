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
// #277: factory also threads `persistence` so the shared
// `SettingsStorageSection` "Clear cache" action wires to the same
// `PersistenceProtocol.latestInProgress()` → `deleteAbandoned(recordName:)`
// shape Sudoku's `SettingsViewModel` uses. Parity-only until MS save-flow
// lands (`latestInProgress()` returns nil today → the delete is a safe
// no-op), but it IS the real protocol method, not a fake button. Version is
// read from `Bundle.main` (CFBundleShortVersionString) at the callsite.
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
public import Persistence

internal import Foundation

public struct LiveRouteFactory: RouteFactory {
    public typealias Route = AppRoute

    private let monetizationController: MonetizationStateController?
    // #277: threaded so the SettingsView "Clear cache" action can delete the
    // active in-progress saved game via `PersistenceProtocol`. Optional so the
    // existing nil-persistence callsites (previews) keep compiling — when nil,
    // SettingsView gets an empty clear-cache closure.
    private let persistence: (any PersistenceProtocol)?
    // U15 (2026-06-03): threaded into `MinesweeperBoardView` so it can mount
    // a `BannerSlotView` mirror below the grid. Optional so the existing
    // Phase 3 callsite (no monetization) keeps compiling; production wires
    // both, previews pass nil.
    private let adProvider: (any AdProvider)?
    private let adGate: AdGate?

    public init(
        monetizationController: MonetizationStateController? = nil,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil,
        persistence: (any PersistenceProtocol)? = nil
    ) {
        self.monetizationController = monetizationController
        self.adProvider = adProvider
        self.adGate = adGate
        self.persistence = persistence
    }

    @MainActor
    public func view(for route: AppRoute, path: Binding<[AppRoute]>?) -> AnyView {
        switch route {
        case .newGame:
            // Difficulty picker — was the old root content; now a destination
            // pushed from the Home "New Game" card / sidebar (#288 / #289).
            return AnyView(NewGameView(path: path ?? .constant([])))
        case .daily:
            // Was unreachable (no AppRoute case). Now resolved here so the
            // Home "Daily" card / sidebar reaches it. The hub shows
            // date-seeded placeholder cards until the Daily MODEL lands (#290).
            return AnyView(MinesweeperDailyHubView(path: path ?? .constant([])))
        case .practice:
            // Was unreachable (no AppRoute case). Now reachable from Home.
            return AnyView(MinesweeperPracticeHubView(path: path ?? .constant([])))
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
            let version = (Bundle.main
                .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
                ?? "1.0.0"
            let persistence = self.persistence
            return AnyView(
                SettingsView(
                    version: version,
                    clearCache: { await Self.clearCache(persistence: persistence) },
                    monetizationController: monetizationController
                )
            )
        }
    }

    /// Deletes the active in-progress saved game, mirroring Sudoku's
    /// `SettingsViewModel.clearCache()`. Parity-only until MS save-flow lands:
    /// `latestInProgress()` returns nil today so this is a safe no-op, but it
    /// exercises the real `PersistenceProtocol` path, not a fake button.
    /// Errors are swallowed — MS has no error funnel wired into Settings yet
    /// (a follow-up matching Sudoku's `errorReporter` thread can add one).
    @MainActor
    private static func clearCache(persistence: (any PersistenceProtocol)?) async {
        guard let persistence else { return }
        do {
            if let candidate = try await persistence.latestInProgress() {
                try await persistence.deleteAbandoned(recordName: candidate.recordName)
            }
        } catch {
            // No-op: see doc comment. MS Settings has no error surface yet.
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
