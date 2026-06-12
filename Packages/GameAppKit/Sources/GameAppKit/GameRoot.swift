// GameRoot — shared game-agnostic app-root container (#448 step 3).
//
// Owns the common Root shape every game shares:
//   - the generic `GameShellUI.RootShellView` (NavigationStackHost + sidebar)
//   - launch-time `bootstrap()` via `.onAppear { Task { … } }`
//   - the bottom toast overlay
//   - SDD-003 Epic 1+2: fullScreenCover modal for board routes + leave confirmation
//
// Game-specific bits stay app-side and are layered on by each app's Root:
// Sudoku adds `.attPrimerSheet(...)` and threads a `ResumePill` into its
// `rootContent`; Minesweeper supplies its own Home as `rootContent`.
//
// SDD-003 Epic 1+2 — Modal game presentation + leave confirmation:
// Board routes are now presented as fullScreenCover modals (R1.1).
// Hub VMs call `viewModel.presentGame(route:)` instead of `path.append(boardRoute)`.
// `GameRoot` owns the modal lifecycle: presents the route factory's board view,
// overlays a `[X]` close button (R1.2), and attaches the "Leave Game?"
// confirmationDialog (AC 2.1–2.3). Save-on-leave reuses each board's existing
// `.onDisappear` flush — no new persistence logic is needed here.
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

public struct GameRoot<Route: Hashable & Sendable, RootContent: View>: View {
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
        shellContent
            .onAppear { Task { await viewModel.bootstrap() } }
            .toastOverlay(
                toastController,
                successTint: successTint,
                failureTint: failureTint
            )
            // SDD-003 Epic 1: fullScreenCover replaces push navigation for board
            // routes on iOS. On macOS `fullScreenCover` is unavailable; the Mac
            // board stays a NavigationStack push (OQ-001 — Designer decision pending).
            // The `#if` keeps the shared target building for both platforms.
            #if os(iOS)
            .fullScreenCover(isPresented: Binding(
                get: { viewModel.isGamePresented },
                set: { presented in
                    // fullScreenCover doesn't support interactive dismiss by default,
                    // so in practice this setter only fires when we set it to `false`.
                    if !presented { viewModel.dismissGame() }
                }
            )) {
                if let route = viewModel.activeGameRoute {
                    GameModalContent(
                        view: routeFactory.view(for: route, path: nil),
                        onClose: { viewModel.requestLeave() },
                        isShowingLeaveConfirmation: Binding(
                            get: { viewModel.isShowingLeaveConfirmation },
                            set: { _ in }   // mutations go through VM methods only
                        ),
                        onCancelLeave: { viewModel.cancelLeave() },
                        onConfirmLeave: { viewModel.confirmLeave() }
                    )
                }
            }
            #endif
    }

    private var shellContent: some View {
        RootShellView(
            path: Binding(get: { viewModel.path }, set: { viewModel.path = $0 }),
            title: title,
            sidebarItems: sidebarItems,
            routeFactory: routeFactory,
            rootContent: rootContent
        )
    }
}

// MARK: - GameModalContent

/// Wraps the route factory's game view with the shared chrome:
///   - top-right `[X]` close button (SDD-003 R1.2)
///   - `confirmationDialog` for the "Leave Game?" confirmation (SDD-003 Epic 2)
///
/// Kept as a separate named type (not an inline closure body) so the
/// `confirmationDialog` modifier has a stable view identity for SwiftUI diffing.
/// Generic over `GameView` so the factory's `AnyView` can be the content.
private struct GameModalContent: View {
    let view: AnyView
    let onClose: () -> Void
    @Binding var isShowingLeaveConfirmation: Bool
    let onCancelLeave: () -> Void
    let onConfirmLeave: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            view
            // SDD-003 R1.2: top-right close button. R1.3 defers any nav-bar-item
            // redesign (OQ-001) to Designer — for now it's a plain overlay button.
            // Padding matches typical iOS safe-area top inset to avoid status bar.
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .padding(10)
                    .background(.regularMaterial, in: Circle())
            }
            .accessibilityLabel(Text("leave.game.close", bundle: .main))
            .padding(.top, 56)
            .padding(.trailing, 20)
        }
        // SDD-003 Epic 2: "Leave Game?" confirmation dialog (AC 2.1).
        // Using confirmationDialog (action sheet on iPhone, alert on Mac) per
        // spec: "native SwiftUI confirmation for now — bottom-sheet is a
        // Designer follow-up". The trigger seam is clean: swap the modifier
        // here when the Designer provides the bottom-sheet spec.
        .confirmationDialog(
            Text("leave.game.title", bundle: .main),
            isPresented: $isShowingLeaveConfirmation,
            titleVisibility: .visible
        ) {
            // AC 2.3: Leave → save + dismiss. LOAD-BEARING cross-package
            // dependency: the save is performed by the board views' .onDisappear
            // hooks — MinesweeperBoardView.persistCurrentState (#455) and Sudoku
            // BoardView.flush (#413) — both bare `Task` so they outlive teardown.
            // If either hook is removed, `leave.game.message` ("will be saved
            // automatically") becomes false. The VM itself does not save.
            Button(role: .destructive) {
                onConfirmLeave()
            } label: {
                Text("leave.game.leave", bundle: .main)
            }
            // AC 2.2: Cancel → return to game, no side effects.
            Button(role: .cancel) {
                onCancelLeave()
            } label: {
                Text("leave.game.cancel", bundle: .main)
            }
        } message: {
            Text("leave.game.message", bundle: .main)
        }
    }
}
