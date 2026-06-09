// HomeViewModel — owns the 4-mode item list + drives navigation.
//
// Per docs/v1/design.md §How.5.4. Routing is delegated through a binding so the
// same VM works inside RootView (bound to its `path`) and standalone in
// previews / unit tests (bound to a local stub array).
//
// #410: the mode set (Daily / Practice / Leaderboard / Settings) + their
// canonical titles / SF Symbols now live in `GameShellUI.HomeMode` (shared with
// Minesweeper). `HomeMode` here is a typealias to that shared enum. This VM
// supplies the Sudoku-specific subtitles + tap actions via `modeItems`, the
// single source for both the Home cards (HomeScreen) and the sidebar
// (RootView derives `SidebarItem`s from the same list).

public import Foundation
public import SwiftUI
public import GameShellUI

/// The shared 4-mode enum. Sudoku has no extra modes, so this is exactly the
/// shared set — kept as a typealias so existing `select(_:)` call sites and
/// tests (`.daily`, `.practice`, …) read unchanged.
public typealias HomeMode = GameShellUI.HomeMode

@MainActor
@Observable
public final class HomeViewModel {
    /// Navigation path store (issue #240): routes through an injected
    /// `Binding<[AppRoute]>` when `RootView` hoists its own array via
    /// `init(path:)`, otherwise a local stub (previews / unit tests).
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

    /// The 4 shared modes bound to Sudoku's subtitles + tap actions. Single
    /// source of truth for both the Home card grid and the sidebar.
    public var modeItems: [HomeModeItem] {
        HomeMode.allCases.map { mode in
            HomeModeItem(
                mode: mode,
                subtitleKey: mode.subtitleKey,
                onTap: { [weak self] in self?.select(mode) }
            )
        }
    }

    public func select(_ mode: HomeMode) {
        // `.leaderboard` is a side-effect (presents Apple's native Game Center
        // dashboard) rather than a stack push — issue #49 (2026-05-20).
        switch mode {
        case .daily:
            path.append(.daily)
        case .practice:
            path.append(.practice)
        case .settings:
            path.append(.settings)
        case .leaderboard:
            GameCenterDashboard.present()
        }
    }
}

private extension HomeMode {
    /// Sudoku-specific subtitles, resolved from Sudoku's `Localizable.xcstrings`.
    var subtitleKey: LocalizedStringKey {
        switch self {
        case .daily: "3 puzzles today"
        case .practice: "Mixed difficulty pool"
        case .leaderboard: "Global / friends"
        case .settings: "Account / language"
        }
    }
}
