// GameRoot — shared game-agnostic app-root container (#448 step 3).
//
// Owns the common Root shape every game shares:
//   - the generic `GameShellUI.RootShellView` (NavigationStackHost + sidebar)
//   - launch-time `bootstrap()` via `.onAppear { Task { … } }`
//   - the bottom toast overlay
//   - SDD-003 Epic 1: fullScreenCover modal for board routes
//   - (retired #674: the modal no longer carries its own top-chrome elapsed
//     timer — see the SDD-003 OQ-001 note below and GameModalContent's doc)
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
// SDD-003 OQ-001 — Timer nav-bar item (retired #674):
// `GameRoot` still owns a `GameChromeState` instance injected via
// `.environment(\.gameChrome, …)` into the fullScreenCover hierarchy, but as of
// #674 neither board reads it any more — the modal's fixed-offset chrome-timer
// capsule overlapped the board's first grid row on some devices, so the timer
// moved permanently into each board's own header/status row instead (both
// push and modal presentation). The seam is kept (not deleted) as a possible
// injection point; see `GameChromeState.swift` for the follow-up note.
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

    // #823: shared join point between a board's terminal-persist Task and
    // the teardown-triggered hub refresh. Not `#if os(iOS)`-gated like
    // `chromeState` — the macOS path-shrink branch in `shellContent` below
    // needs it too (mac boards are a NavigationStack push, not a
    // fullScreenCover). See `TerminalPersistJoin`'s doc for the full race.
    @State private var persistJoin = TerminalPersistJoin()

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
            // #761: route views (e.g. the Daily hubs) read this to refresh
            // after a game session ends — see `GameRootViewModel.sessionTeardownCount`.
            .environment(\.gameSessionTeardownCount, viewModel.sessionTeardownCount)
            // #823: board views register their in-flight terminal-persist
            // Task here before dismissing — see `TerminalPersistJoin`.
            .environment(\.terminalPersistJoin, persistJoin)
            // #685: moved here from the former `universalRootModifiers` helper
            // (called once from the plain `makeGameApp` function, outside any
            // View's own `body`). That outer attachment point never got
            // revisited by SwiftUI's Observation-driven invalidation once
            // mounted — flipping `showGameCenterSignedOutAlert` never made the
            // alert reappear (confirmed via instrumented sim repro: the
            // Binding's `get` fired at initial mount and never again after the
            // flag flipped true). Mounting it inside `GameRoot.body` — the
            // same pattern the `fullScreenCover` binding below already uses
            // successfully — keeps it inside an actively re-evaluated View body
            // so the Observable flag reliably re-triggers presentation.
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
                        // #823: pass the join so the teardown counter bump
                        // waits (bounded) for any in-flight terminal-persist
                        // save the dismissing board registered.
                        viewModel.dismissGame(persistJoin: persistJoin)
                        chromeState.reset()
                    }
                }
            )) {
                if let route = viewModel.activeGameRoute {
                    GameModalContent(
                        view: routeFactory.view(for: route, path: nil),
                        chromeState: chromeState
                    )
                    // #674: the chrome timer capsule is retired — the boards
                    // render their own in-header timer and no longer read this
                    // key. The injection stays only so the dormant seam keeps
                    // compiling until the follow-up removal.
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
                    // for non-board pops too. #761: also bumps the teardown
                    // counter so environment-observing views (e.g. the Daily
                    // hubs) refresh, mirroring `dismissGame()`'s iOS wiring.
                    // #912: delegated to `handlePathShrink` — on iOS this
                    // branch ALSO fires once at board OPEN (`GameBoardRedirect`
                    // popping its synthetic push entry), which used to trigger
                    // a spurious refresh/teardown at open time, not just at a
                    // genuine close; `handlePathShrink` filters that case out
                    // via `isGamePresented`. #823: same join as the iOS
                    // fullScreenCover branch above — macOS boards pop `path`
                    // instead of dismissing a cover, but the race is identical.
                    if newPath.count < viewModel.path.count {
                        viewModel.handlePathShrink(persistJoin: persistJoin)
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

/// Wraps the route factory's game view for the fullScreenCover modal.
///
/// #674: previously also rendered a top-left elapsed-timer capsule
/// (SDD-003 OQ-001) at a fixed `.padding(.top, 56)`. That fixed offset
/// overlapped the board's own header row / grid first row on some devices
/// (owner report, #674) because it was positioned independent of where the
/// board's actual header landed. The timer now lives permanently in each
/// board's own header/status row (SudokuUI.BoardView / MinesweeperUI's
/// MinesweeperBoardView, mirroring MS's #663 uplift) instead of this
/// separate chrome layer, so `GameModalContent` no longer renders anything
/// beyond the game view itself.
///
/// Leave is handled by the unified PauseOverlayView in each board, which
/// provides a Leave button that calls `dismiss()` directly (Epic 2 removed
/// the former ✕ close button + confirmationDialog pattern).
///
/// Kept as a separate named type (not an inline closure body) so view identity
/// is stable across body re-evaluations.
private struct GameModalContent: View {
    let view: AnyView
    /// #674: neither board still feeds `chromeState.elapsedLabel` /
    /// `isHidingChrome` (both retired their chrome-timer calls once their
    /// header/status row took over rendering). Kept as an injection seam
    /// rather than deleted outright — see the follow-up note in
    /// `GameChromeState.swift` — but no longer read here.
    let chromeState: GameChromeState

    var body: some View {
        view
    }
}
