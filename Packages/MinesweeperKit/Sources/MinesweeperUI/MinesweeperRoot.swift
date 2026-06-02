// MinesweeperRoot — Minesweeper's app-entry container.
//
// Thin wrapper over `GameShellUI.RootShellView` (PR X3 extraction). The
// generic shell owns the NavigationStackHost shape + sidebar rendering;
// MinesweeperRoot supplies:
//   - The path (`[AppRoute]`) state.
//   - The sidebar items (New Game / Settings).
//   - The root content (`NewGameView`).
//   - A `RouteFactory<AppRoute>` for destination resolution.
//
// Mirrors the shape of `SudokuKit.RootView` but is radically simpler —
// Sudoku threads a RootViewModel + monetization + toast surfaces; Minesweeper
// just holds local navigation state. Persistence / monetization / Daily /
// Practice are deferred until the product surface is designed.

public import SwiftUI
public import GameShellUI

public struct MinesweeperRoot: View {
    @State private var path: [AppRoute] = []

    private let routeFactory: any RouteFactory<AppRoute>

    public init(routeFactory: any RouteFactory<AppRoute>) {
        self.routeFactory = routeFactory
    }

    public var body: some View {
        RootShellView(
            path: $path,
            title: "Minesweeper",
            sidebarItems: sidebarItems,
            routeFactory: routeFactory,
            rootContent: {
                NewGameView(path: $path)
            }
        )
    }

    // Sidebar mirrors the two Standard-tier entries. New Game pops back to
    // root (root content is NewGameView, so an empty path == picker visible).
    // Settings pushes its placeholder destination.
    //
    // §設計決定: same as Sudoku's RootView — direct `path.append` / mutation
    // inside the onTap closure (not `NavigationLink(value:)`) so the mutation
    // and the destination registry share the detail-pane scope on macOS
    // NavigationSplitView. Cross-pane value-link lookup is the documented
    // footgun (Sudoku issue #197).
    private var sidebarItems: [SidebarItem<AppRoute>] {
        [
            SidebarItem(
                id: "newGame",
                titleKey: "New Game",
                systemImage: "play.circle",
                onTap: { path.removeAll() }
            ),
            SidebarItem(
                id: "settings",
                titleKey: "Settings",
                systemImage: "gear",
                onTap: { path.append(.settings) }
            ),
        ]
    }
}

// Preview-only stub. Kept private so production callers must still construct
// a real `RouteFactory` (e.g. `LiveRouteFactory`) via the composition root.
@MainActor
private struct PreviewRouteFactory: RouteFactory {
    typealias Route = AppRoute

    func view(for route: AppRoute, path: Binding<[AppRoute]>?) -> AnyView {
        switch route {
        case .board(let difficulty, let seed):
            return AnyView(Text("Preview board: \(String(describing: difficulty)) seed=\(seed)"))
        case .settings:
            return AnyView(Text("Preview settings"))
        }
    }
}

#Preview {
    MinesweeperRoot(routeFactory: PreviewRouteFactory())
}
