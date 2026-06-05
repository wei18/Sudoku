// MinesweeperRoot — Minesweeper's app-entry container.
//
// Thin wrapper over `GameShellUI.RootShellView` (PR X3 extraction). The
// generic shell owns the NavigationStackHost shape + sidebar rendering;
// MinesweeperRoot supplies:
//   - The path (`[AppRoute]`) state.
//   - The sidebar items (New Game / Daily / Practice / Leaderboard / Settings).
//   - The root content (`MinesweeperHomeView`).
//   - A `RouteFactory<AppRoute>` for destination resolution.
//
// Mirrors the shape of `SudokuKit.RootView` — Home is the root content; the
// sidebar mirrors the Home mode cards. #288 / #289 (2026-06-04) swapped the
// root content from the bare `NewGameView` to the Home mode-card surface and
// made the Daily / Practice hubs reachable.

public import SwiftUI
public import GameShellUI
public import MonetizationCore
public import MonetizationUI

public struct MinesweeperRoot: View {
    @State private var path: [AppRoute] = []
    // #313: owns the launch-time Game Center auth handshake, kicked from the
    // `.task` below. Mirrors `SudokuUI.RootView`'s `RootViewModel` wiring.
    @State private var viewModel: MinesweeperRootViewModel
    @Environment(\.theme) private var theme

    private let routeFactory: any RouteFactory<AppRoute>
    // U15 (2026-06-03): mounts `.toastOverlay(...)` at the Root so purchase /
    // restore results land on a single shared bottom overlay (mirrors
    // SudokuUI.RootView). Optional so the existing one-argument init keeps
    // compiling for previews.
    private let toastController: ToastController?
    // #288 / #289: forwarded to `MinesweeperHomeView` for its banner slot +
    // Remove Ads card. Home is the root content (not a destination), so the
    // route factory can't thread these for it — Root passes them directly,
    // mirroring `SudokuUI.RootView`.
    private let adProvider: (any AdProvider)?
    private let adGate: AdGate?
    private let monetizationController: MonetizationStateController?

    public init(
        viewModel: MinesweeperRootViewModel,
        routeFactory: any RouteFactory<AppRoute>,
        toastController: ToastController? = nil,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil,
        monetizationController: MonetizationStateController? = nil
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.routeFactory = routeFactory
        self.toastController = toastController
        self.adProvider = adProvider
        self.adGate = adGate
        self.monetizationController = monetizationController
    }

    public var body: some View {
        RootShellView(
            path: $path,
            title: "Minesweeper",
            sidebarItems: sidebarItems,
            routeFactory: routeFactory,
            rootContent: {
                MinesweeperHomeView(
                    viewModel: MinesweeperHomeViewModel(path: $path),
                    adProvider: adProvider,
                    adGate: adGate,
                    monetizationController: monetizationController
                )
            }
        )
        // #313: launch-time Game Center auth handshake. Mirrors
        // `SudokuUI.RootView`'s `.task { await viewModel.bootstrap() }`.
        // Idempotent — a `.task` re-entry won't re-trigger GameKit auth.
        .task { await viewModel.bootstrap() }
        .toastOverlay(
            toastController,
            successTint: theme.status.success.resolved,
            failureTint: theme.status.error.resolved
        )
    }

    // Sidebar mirrors the Home mode cards. New Game / Daily / Practice /
    // Settings push an `AppRoute`; Leaderboard is a no-op stub until MS Game
    // Center lands (#291) — present in the list for parity but inert.
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
                systemImage: "plus.circle",
                onTap: { path.append(.newGame) }
            ),
            SidebarItem(
                id: "daily",
                titleKey: "Daily",
                systemImage: "calendar",
                onTap: { path.append(.daily) }
            ),
            SidebarItem(
                id: "practice",
                titleKey: "Practice",
                systemImage: "dice",
                onTap: { path.append(.practice) }
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

// #313: `MinesweeperRoot` now requires a `MinesweeperRootViewModel` (which
// holds a `GameCenterClient`). Constructing a GC stub here would need to name
// the GC protocol's `SudokuEngine.Difficulty` (not importable from this leaf
// module without a new dep), so the previous root-level `#Preview` is removed
// — mirroring `SudokuUI.RootView`, which has no `#Preview` either (the
// composition-root view is exercised via `MinesweeperAppComposition.preview()`
// + the app target, not a leaf-module preview). Individual surfaces
// (`MinesweeperHomeView`, hubs, board) keep their own previews.
