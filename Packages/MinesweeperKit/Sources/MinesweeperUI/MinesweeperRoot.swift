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
// #448 step 3: shared `GameRoot` (Root shell + onAppear-bootstrap + toast).
// Public because the init's `MinesweeperRootViewModel` is a typealias over
// `GameRootViewModel`.
public import GameAppKit

public struct MinesweeperRoot: View {
    // #313: owns the launch-time Game Center auth handshake. Its `path` (from
    // `GameRootViewModel`) is the single navigation array — bound to the
    // sidebar, the Home cards, and `GameRoot`'s NavigationStack. Mirrors
    // `SudokuUI.RootView`'s `RootViewModel` wiring.
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

    // #410: one `MinesweeperHomeViewModel` drives BOTH the Home cards and the
    // sidebar, so the mode list (Daily / Practice / Leaderboard / Settings) +
    // their tap actions come from a single source. Bound to Root's `path`.
    // #513: `authState` forwarded so the leaderboard card can gate on it.
    // #513 fix: `showGameCenterSignedOutAlert` binding threaded to the stable
    // `GameRootViewModel` flag so the `.alert` survives re-renders.
    private var homeViewModel: MinesweeperHomeViewModel {
        MinesweeperHomeViewModel(
            path: Binding(get: { viewModel.path }, set: { viewModel.path = $0 }),
            authState: viewModel.authState,
            showGameCenterSignedOutAlert: Binding(
                get: { viewModel.showGameCenterSignedOutAlert },
                set: { viewModel.showGameCenterSignedOutAlert = $0 }
            )
        )
    }

    public var body: some View {
        // #448 step 3: the common Root shape (RootShellView + bootstrap + toast)
        // now lives in `GameAppKit.GameRoot`. This also swaps the former
        // `.task { bootstrap() }` for GameRoot's `.onAppear { Task { … } }` —
        // fixing the latent arm64 device-Release link risk (Xcode 26 lowers
        // every `.task` overload to `task(name:…)`, whose descriptor links
        // undefined in the device Release archive). #361
        GameRoot(
            viewModel: viewModel,
            title: "Minesweeper",
            sidebarItems: HomeModeItem.sidebarItems(from: homeViewModel.modeItems),
            routeFactory: routeFactory,
            toastController: toastController,
            successTint: theme.status.success.resolved,
            failureTint: theme.status.error.resolved
        ) {
            MinesweeperHomeView(
                viewModel: homeViewModel,
                adProvider: adProvider,
                adGate: adGate,
                monetizationController: monetizationController
            )
        }
        // #513 fix: alert bound to the stable `GameRootViewModel` flag (not the
        // per-render MinesweeperHomeViewModel). Mounting here keeps the binding
        // alive across SwiftUI re-renders — the "computed-property HomeViewModel"
        // footgun means any alert on MinesweeperHomeView's transient VM never fires.
        .alert(
            "Sign in to Game Center",
            isPresented: Binding(
                get: { viewModel.showGameCenterSignedOutAlert },
                set: { viewModel.showGameCenterSignedOutAlert = $0 }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Sign in to Game Center to compare with others.")
        }
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
