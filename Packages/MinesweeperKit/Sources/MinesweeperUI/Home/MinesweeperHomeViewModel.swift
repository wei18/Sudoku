// MinesweeperHomeViewModel — owns the mode-card list + drives navigation.
//
// Mirror of `SudokuUI.HomeViewModel` (#288 / #289, 2026-06-04). Routing is
// delegated through `GameShellUI.RoutePath<AppRoute>` (#240) so the same VM
// works inside `MinesweeperRoot` (bound to its `path`) and standalone in
// previews / unit tests (bound to a local stub array).
//
// Card list differs from Sudoku: MS keeps a "New Game" entry (its primary
// difficulty picker) ahead of Daily / Practice / Leaderboard / Settings.

public import Foundation
public import SwiftUI
import GameShellUI

public enum MinesweeperHomeMode: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case newGame
    case daily
    case practice
    case leaderboard
    case settings

    public var id: String { rawValue }
}

@MainActor
@Observable
public final class MinesweeperHomeViewModel {
    /// Navigation path store (#240): routes through an injected
    /// `Binding<[AppRoute]>` when `MinesweeperRoot` hoists its own array,
    /// otherwise a local stub (previews / unit tests).
    private var routePath: RoutePath<AppRoute>

    /// Single public view of the navigation path. Callers do not need to know
    /// which mode (injected binding / local stub) is active.
    public var path: [AppRoute] {
        get { routePath.effectivePath }
        set { routePath.effectivePath = newValue }
    }

    public init(path: Binding<[AppRoute]>? = nil) {
        self.routePath = RoutePath(path)
    }

    public func select(_ mode: MinesweeperHomeMode) {
        switch mode {
        case .newGame:
            path.append(.newGame)
        case .daily:
            path.append(.daily)
        case .practice:
            path.append(.practice)
        case .settings:
            path.append(.settings)
        case .leaderboard:
            // No-op until MS Game Center lands (#291). Mirroring Sudoku (#49),
            // Leaderboard is a modal GC side-effect, never a stack push — so
            // there is no `.leaderboard` route. The Home card is rendered
            // `.disabled` so this branch is unreachable from the UI today; it
            // stays here as the documented seam for the future GC present call.
            break
        }
    }
}
