// Game2048Root — Tiles2048's app-entry container.
//
// M4: replaces M3's plain NavigationStack push with `GameAppKit.GameRoot`
// (shared GameRoot modal + bootstrap + toast — #448 step 3 pattern). Mirrors
// MinesweeperRoot exactly in shape.
//
// Theme: `Game2048Theme()` warm-tile palette is injected at the Root so every
// mounted view resolves the amber/sand tokens. Mirrors Minesweeper's
// `.environment(\.theme, MinesweeperTheme())` in `MinesweeperAppComposition.rootView`.
//
// Navigation: `Game2048HomeViewModel` drives BOTH the Home cards and the
// sidebar (single source), bound to Root's `viewModel.path`. Mirrors
// `MinesweeperRoot`'s `MinesweeperHomeViewModel` shape.

public import SwiftUI
public import GameShellUI
public import MonetizationCore
public import MonetizationUI
public import GameAppKit

public struct Game2048Root: View {
    @State private var viewModel: Game2048RootViewModel
    @Environment(\.theme) private var theme

    private let routeFactory: any RouteFactory<AppRoute>
    private let toastController: ToastController?
    private let adProvider: (any AdProvider)?
    private let adGate: AdGate?
    private let monetizationController: MonetizationStateController?

    public init(
        viewModel: Game2048RootViewModel,
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

    // One `Game2048HomeViewModel` drives BOTH the Home cards and the sidebar.
    // Bound to Root's `path` — mirrors MinesweeperRoot's homeViewModel shape.
    private var homeViewModel: Game2048HomeViewModel {
        Game2048HomeViewModel(path: Binding(get: { viewModel.path }, set: { viewModel.path = $0 }))
    }

    public var body: some View {
        // GameRoot (#448 step 3): shared RootShellView + bootstrap + toast.
        // `.onAppear { Task { … } }` inside GameRoot — fixes the latent arm64
        // device-Release link risk from Xcode 26 `.task` lowering (#361).
        GameRoot(
            viewModel: viewModel,
            title: "2048 Tiles",
            sidebarItems: HomeModeItem.sidebarItems(from: homeViewModel.modeItems),
            routeFactory: routeFactory,
            toastController: toastController,
            successTint: theme.status.success.resolved,
            failureTint: theme.status.error.resolved
        ) {
            Game2048HomeView(
                viewModel: homeViewModel,
                adProvider: adProvider,
                adGate: adGate,
                monetizationController: monetizationController
            )
        }
    }
}

// No root-level #Preview — constructing Game2048RootViewModel requires a
// GameCenterClient; mirroring MinesweeperRoot (which also has no #Preview
// for the same reason). Individual surfaces (HomeView, hubs, board) have
// their own previews. Use Game2048AppComposition.preview() to exercise the
// full composition.
