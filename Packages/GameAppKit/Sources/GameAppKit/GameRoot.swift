// GameRoot — shared game-agnostic app-root container (#448 step 3).
//
// Owns the common Root shape every game shares:
//   - the generic `GameShellUI.RootShellView` (NavigationStackHost + sidebar)
//   - launch-time `bootstrap()` via `.onAppear { Task { … } }`
//   - the bottom toast overlay
//   - SDD-003 Epic 1: fullScreenCover modal for board routes
//   - SDD-003 OQ-001: top-chrome elapsed timer in the modal (nav-bar-item style)
//
// Game-specific bits stay app-side and are layered on by each app's Root:
// Sudoku adds `.attPrimerSheet(...)` and threads a `ResumePill` into its
// `rootContent`; Minesweeper supplies its own Home as `rootContent`.
//
// SDD-003 Epic 1 — Modal game presentation:
// Board routes are presented as fullScreenCover modals (R1.1).
// Hub VMs call `viewModel.presentGame(route:)` instead of `path.append(boardRoute)`.
// The Pause overlay's Leave button now handles the leave flow directly (no separate
// confirmationDialog — Epic 2 replaced by the unified pause menu).
//
// SDD-003 OQ-001 — Timer nav-bar item:
// `GameRoot` owns a `GameChromeState` instance injected via
// `.environment(\.gameChrome, …)` into the fullScreenCover hierarchy. Board views
// read this key from `@Environment` and call `chromeState.updateElapsed(_:)` each
// tick. `GameModalContent` renders the label as a leading capsule badge.
// When `gameChrome` is nil (macOS push / snapshot / preview) the board views
// keep their own in-board timer and this path is never reached.
//
// Note on `.onAppear { Task { … } }` (NOT `.task { … }`): the original #361 arm64
// device Release link failure — an opaque `.task` descriptor linking undefined
// (sim / macOS / Debug build fine) — was at THIS app-root composition bootstrap, so
// it stays on `.onAppear`. `bootstrap()` is a one-shot boot with its own idempotency
// guard, so `.task`'s disappear-cancellation isn't needed. NOTE (#607): the rule is
// scoped to the app-root bootstrap, NOT a blanket ban — leaf-view one-shot `.task`
// bootstraps (Settings / Daily hub / banner) verify link-clean in an arm64 device
// Release archive (build 202606260559). #361 / #4499

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

    // SDD-003 OQ-001: single chrome state instance, owned here so it outlives
    // individual modal presentations. Reset on dismiss so a stale label from a
    // previous game never bleeds into a new one. `@State` gives it stable
    // identity across body re-evaluations — the board view holds an `@Environment`
    // reference to the same object and mutates it in its timer loop.
    #if os(iOS)
    @State private var chromeState = GameChromeState()
    #endif

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
            // board stays a NavigationStack push.
            // The `#if` keeps the shared target building for both platforms.
            #if os(iOS)
            .fullScreenCover(isPresented: Binding(
                get: { viewModel.isGamePresented },
                set: { presented in
                    // fullScreenCover doesn't support interactive dismiss by default,
                    // so in practice this setter only fires when we set it to `false`.
                    if !presented {
                        viewModel.dismissGame()
                        chromeState.reset()
                    }
                }
            )) {
                if let route = viewModel.activeGameRoute {
                    GameModalContent(
                        view: routeFactory.view(for: route, path: nil),
                        chromeState: chromeState
                    )
                    // SDD-003 OQ-001: inject the chrome state into the modal
                    // hierarchy so the board view can find it via
                    // `@Environment(\.gameChrome)` and update the elapsed label
                    // each tick. The board also reads this key to know it is in
                    // a modal and should hide its own in-board timer.
                    .environment(\.gameChrome, chromeState)
                }
            }
            #endif
    }

    private var shellContent: some View {
        RootShellView(
            path: Binding(
                get: { viewModel.path },
                set: { newPath in
                    // #675: on macOS, board routes are a `NavigationStack`
                    // push (no `fullScreenCover`/`dismissGame()` involved —
                    // see `GameBoardRedirect`), so a board's Leave / completion
                    // Close pops `path` directly (`BoardView+Completion.exitToHub`)
                    // instead of going through `dismissGame()`. Any shrink of
                    // `path` is treated as "a route just went away" and
                    // refreshes the resume pill the same way `dismissGame()`
                    // does on iOS — cheap (one CK query), and harmless to run
                    // for non-board pops too.
                    if newPath.count < viewModel.path.count {
                        Task { await viewModel.refreshResumeCandidate() }
                    }
                    viewModel.path = newPath
                }
            ),
            title: title,
            sidebarItems: sidebarItems,
            routeFactory: routeFactory,
            rootContent: rootContent
        )
    }
}

// MARK: - GameModalContent

/// Wraps the route factory's game view with the shared chrome:
///   - top-left elapsed timer capsule (SDD-003 OQ-001)
///
/// Leave is no longer handled here — the unified PauseOverlayView in each
/// board provides a Leave button that calls `dismiss()` directly, replacing
/// the former ✕ close button + confirmationDialog pattern (Epic 2 removed).
///
/// Kept as a separate named type (not an inline closure body) so view identity
/// is stable across body re-evaluations.
private struct GameModalContent: View {
    let view: AnyView
    /// SDD-003 OQ-001: shared observable that the board view updates with the
    /// current elapsed string. Observed here so the timer badge re-renders
    /// when `elapsedLabel` changes without re-creating `GameModalContent`.
    let chromeState: GameChromeState

    var body: some View {
        ZStack(alignment: .top) {
            view
            // SDD-003 OQ-001: nav-bar-item-style top chrome row.
            // Timer sits at leading edge below the status bar safe area.
            // #518: hidden when the board signals terminal state via
            // `chromeState.isHidingChrome` so the completion overlay (which is
            // a child of `view`) can cover the full screen without the chrome
            // row bleeding through on top of the result card.
            if !chromeState.isHidingChrome {
                HStack {
                    // Timer capsule — visible only once the board starts ticking.
                    if let label = chromeState.elapsedLabel {
                        Label(label, systemImage: "timer")
                            .font(.system(.subheadline, design: .monospaced).monospacedDigit())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                            .accessibilityLabel(Text("Elapsed time \(label)"))
                            .transition(.opacity)
                    }
                    Spacer()
                }
                .padding(.top, 56)
                .padding(.horizontal, 20)
                .transition(.opacity)
            }
        }
    }
}
