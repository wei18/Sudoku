// MinesweeperHomeViewModel — owns the mode-item list + drives navigation.
//
// Mirror of `SudokuUI.HomeViewModel` (#288 / #289, 2026-06-04). Routing is
// delegated through `GameShellUI.RoutePath<AppRoute>` (#240) so the same VM
// works inside `MinesweeperRoot` (bound to its `path`) and standalone in
// previews / unit tests (bound to a local stub array).
//
// #410: the mode set + canonical titles / SF Symbols now live in the shared
// `GameShellUI.HomeMode` (Daily / Practice / Leaderboard / Settings), identical
// to Sudoku. The erroneous extra `newGame` mode (Sudoku never had one) is
// REMOVED — MS reaches its difficulty picker through Practice, like Sudoku.
// This VM supplies MS-specific subtitles + tap actions via `modeItems`, the
// single source for both the Home cards (HomeScreen) and the sidebar.

public import Foundation
public import SwiftUI
public import GameShellUI

/// The shared 4-mode enum — identical to Sudoku after the #410 New Game
/// removal. Kept as a typealias so existing `select(_:)` call sites and tests
/// (`.daily`, `.practice`, …) read unchanged.
public typealias MinesweeperHomeMode = GameShellUI.HomeMode

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

    /// The 4 shared modes bound to MS's subtitles + tap actions. Single source
    /// of truth for both the Home card grid and the sidebar.
    public var modeItems: [HomeModeItem] {
        HomeMode.allCases.map { mode in
            HomeModeItem(
                mode: mode,
                subtitleKey: mode.subtitleKey,
                onTap: { [weak self] in self?.select(mode) }
            )
        }
    }

    public func select(_ mode: MinesweeperHomeMode) {
        switch mode {
        case .daily:
            path.append(.daily)
        case .practice:
            path.append(.practice)
        case .settings:
            path.append(.settings)
        case .leaderboard:
            // #291: present Apple's native Game Center dashboard. Mirroring
            // Sudoku (#49), Leaderboard is a modal GC side-effect, never a
            // stack push — so there is no `.leaderboard` route. Passing `nil`
            // opens the full leaderboards listing (all 3 best-time boards).
            MinesweeperGameCenterDashboard.present(leaderboardId: nil)
        }
    }
}

private extension MinesweeperHomeMode {
    /// MS-specific subtitles, resolved from MS's `Localizable.xcstrings`.
    var subtitleKey: LocalizedStringKey {
        switch self {
        case .daily: "3 boards today"
        case .practice: "All difficulties"
        case .leaderboard: "Best times"
        case .settings: "Purchases / about"
        }
    }
}
