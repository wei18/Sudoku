// Game2048HomeViewModel — owns the mode-item list + drives navigation.
// Mirrors MinesweeperHomeViewModel exactly.
//
// Routing through `GameShellUI.RoutePath<AppRoute>` so the same VM works
// inside `Game2048Root` (bound to its `path`) and standalone in previews.

public import Foundation
public import SwiftUI
public import GameShellUI

public typealias Game2048HomeMode = GameShellUI.HomeMode

@MainActor
@Observable
public final class Game2048HomeViewModel {
    private var routePath: RoutePath<AppRoute>

    public var path: [AppRoute] {
        get { routePath.effectivePath }
        set { routePath.effectivePath = newValue }
    }

    public init(path: Binding<[AppRoute]>? = nil) {
        self.routePath = RoutePath(path)
    }

    public var modeItems: [HomeModeItem] {
        HomeMode.allCases.map { mode in
            HomeModeItem(
                mode: mode,
                subtitleKey: mode.subtitleKey,
                onTap: { [weak self] in self?.select(mode) }
            )
        }
    }

    public func select(_ mode: Game2048HomeMode) {
        switch mode {
        case .daily:
            path.append(.daily)
        case .practice:
            path.append(.practice)
        case .settings:
            path.append(.settings)
        case .leaderboard:
            // Present Apple's native GC dashboard (modal side-effect, never a route).
            Game2048GameCenterDashboard.present(leaderboardId: nil)
        }
    }
}

private extension Game2048HomeMode {
    var subtitleKey: LocalizedStringKey {
        switch self {
        case .daily: "Today's seeded board"
        case .practice: "Unlimited classic play"
        case .leaderboard: "Top daily scores"
        case .settings: "Purchases / about"
        }
    }
}
