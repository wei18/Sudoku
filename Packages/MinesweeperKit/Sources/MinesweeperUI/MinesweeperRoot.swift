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
public import MonetizationUI

public struct MinesweeperRoot: View {
    @State private var path: [AppRoute] = []

    private let routeFactory: any RouteFactory<AppRoute>
    // U15 (2026-06-03): mounts `.toastOverlay(...)` at the Root so purchase /
    // restore results land on a single shared bottom overlay (mirrors
    // SudokuUI.RootView). Optional so the existing one-argument init keeps
    // compiling for previews.
    private let toastController: ToastController?

    public init(
        routeFactory: any RouteFactory<AppRoute>,
        toastController: ToastController? = nil
    ) {
        self.routeFactory = routeFactory
        self.toastController = toastController
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
        // MS uses SwiftUI primitive tints until MS theme tokens land. Sudoku
        // reads `theme.status.success/error` via SudokuUI's theme env; MS
        // mirrors the call shape without the theme dep.
        .toastOverlay(
            toastController,
            successTint: .green,
            failureTint: .red
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
