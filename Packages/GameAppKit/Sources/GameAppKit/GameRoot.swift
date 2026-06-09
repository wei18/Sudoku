// GameRoot — shared game-agnostic app-root container (#448 step 3).
//
// Owns the common Root shape every game shares:
//   - the generic `GameShellUI.RootShellView` (NavigationStackHost + sidebar)
//   - launch-time `bootstrap()` via `.onAppear { Task { … } }`
//   - the bottom toast overlay
//
// Game-specific bits stay app-side and are layered on by each app's Root:
// Sudoku adds `.attPrimerSheet(...)` and threads a `ResumePill` into its
// `rootContent`; Minesweeper supplies its own Home as `rootContent`.
//
// Note on `.onAppear { Task { … } }` (NOT `.task { … }`): Xcode 26's SwiftUI
// lowers EVERY `.task` overload to `task(name:priority:file:line:_:)`, whose
// opaque-type descriptor links undefined in the arm64 device Release archive
// (sim / macOS / Debug build fine). `bootstrap()` is a one-shot boot with its
// own idempotency guard, so `.task`'s disappear-cancellation isn't needed.
// Hosting this here fixes the latent MinesweeperRoot `.task` device-Release
// link risk for free. #361 / #4499

public import SwiftUI
public import GameShellUI
public import MonetizationUI

public struct GameRoot<Route: Hashable, RootContent: View>: View {
    // The app-side Root owns the VM as `@State`; GameRoot holds the same
    // `@Observable` reference. Property access in `body` registers observation,
    // so a plain stored reference (not a second `@State`) is correct here and
    // keeps single ownership.
    private let viewModel: GameRootViewModel<Route>
    private let title: LocalizedStringKey
    private let sidebarItems: [SidebarItem<Route>]
    private let routeFactory: any RouteFactory<Route>
    private let toastController: ToastController?
    private let successTint: Color
    private let failureTint: Color
    private let rootContent: () -> RootContent

    public init(
        viewModel: GameRootViewModel<Route>,
        title: LocalizedStringKey,
        sidebarItems: [SidebarItem<Route>],
        routeFactory: any RouteFactory<Route>,
        toastController: ToastController?,
        successTint: Color,
        failureTint: Color,
        @ViewBuilder rootContent: @escaping () -> RootContent
    ) {
        self.viewModel = viewModel
        self.title = title
        self.sidebarItems = sidebarItems
        self.routeFactory = routeFactory
        self.toastController = toastController
        self.successTint = successTint
        self.failureTint = failureTint
        self.rootContent = rootContent
    }

    public var body: some View {
        RootShellView(
            path: Binding(get: { viewModel.path }, set: { viewModel.path = $0 }),
            title: title,
            sidebarItems: sidebarItems,
            routeFactory: routeFactory,
            rootContent: rootContent
        )
        .onAppear { Task { await viewModel.bootstrap() } }
        .toastOverlay(
            toastController,
            successTint: successTint,
            failureTint: failureTint
        )
    }
}
