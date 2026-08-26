// RootShellView — generic app root: a 3-tab `sidebarAdaptable` TabView with
// one navigation path per tab (#1020, design.md §2.1–§2.3, §3.7).
//
// One artifact serves all three surfaces: iPhone floating glass tab bar,
// iPad regular sidebar (collapsible back to a tab bar), macOS sidebar —
// per HIG *Sidebars* ("When you use the sidebarAdaptable style of tab view to
// present a sidebar, you choose whether to display a sidebar or a tab bar when
// your app opens"). The hand-authored sidebar `List`, its per-item config array,
// the compact/regular split-view host and the HOME screen it hosted are all
// gone — `sidebarAdaptable` owns that chrome now.
//
// Each tab owns its own `NavigationStack` path, so finishing a game in Practice
// does not tear down what the player had stacked in Today (§2.1 diagram). The
// host supplies `path(_:)`, one binding per tab; `.navigationDestination(for:)`
// sits at each stack's ROOT (never inside a lazy container) and resolves through
// the shared `RouteFactory`, handing that tab's own binding down so a
// destination's further pushes land on the same stack.
//
// #763 / #1019 / #1020 — pause & completion must lock the whole shell, and the
// way they do it is load-bearing. Two rules, both paid for in bisection:
//
// 1. The overlay renders as a ZStack SIBLING of the TabView, never inside it
//    (#1019 evidence 01-04): `sidebarAdaptable` generates its own chrome, so
//    any lock has to cover the whole TabView — and an overlay mounted inside
//    that subtree would have its OWN Resume / Close locked too, leaving the
//    player in an undismissable modal.
//
// 2. NOTHING in this body may change while a board is pushed. On macOS,
//    re-running the body that builds a `sidebarAdaptable` TabView UNMOUNTS
//    whatever is pushed in the selected tab's `NavigationStack` — the path
//    binding survives intact, but the destination view is destroyed, so the
//    stack silently falls back to its root. #1020 hit this three ways, each
//    confirmed and then removed by bisection against the macOS XCUITest:
//      - `.onPreferenceChange(BoardModalOverlayActivePreferenceKey)` here
//        (fired -> board gone, even when its closure wrote nothing),
//      - `.disabled(...)` toggling on the TabView,
//      - reading `coordinator.content` directly in this body.
//    So there is no `.disabled()` and no preference observer left. The lock is
//    the overlay's own full-screen scrim plus `.accessibilityAddTraits(.isModal)`,
//    which is what actually pruned the sidebar rows from the a11y tree in the
//    #1019 spike (evidence 06-10) and what `test_pauseOverlayLocksShellOnMac_1019`
//    verifies. See `BoardModalOverlayHoist.swift`.

public import SwiftUI

public struct RootShellView<Route: Hashable, TabRoot: View>: View {
    @Binding private var selectedTab: AppTab
    private let path: (AppTab) -> Binding<[Route]>
    private let routeFactory: any RouteFactory<Route>
    private let tabRoot: (AppTab) -> TabRoot

    // #1019: owns the hoisted overlay. `@State` so its identity survives body
    // re-evaluations; injected into the TabView subtree so a pushed board can
    // register its overlay for rendering out here instead.
    @State private var coordinator = BoardModalOverlayCoordinator()

    /// - Parameters:
    ///   - selectedTab: the shell's current tab. Plain two-way binding — a tab
    ///     switch carries no side effects (§3.6.2 / N-AB: switching tabs is not
    ///     a pop, so it must not trigger a resume-pill refresh).
    ///   - path: the navigation path binding for a given tab. Called per tab per
    ///     render; the host is expected to return a binding onto stable storage
    ///     (e.g. `GameAppKit.GameRootViewModel.paths`).
    ///   - routeFactory: resolves a `Route` into its destination view.
    ///   - tabRoot: the per-app root content for a given tab (Today hub /
    ///     Practice hub / Progress). Supplied by the app so the shell stays
    ///     game-agnostic.
    public init(
        selectedTab: Binding<AppTab>,
        path: @escaping (AppTab) -> Binding<[Route]>,
        routeFactory: any RouteFactory<Route>,
        @ViewBuilder tabRoot: @escaping (AppTab) -> TabRoot
    ) {
        self._selectedTab = selectedTab
        self.path = path
        self.routeFactory = routeFactory
        self.tabRoot = tabRoot
    }

    public var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    Tab(tab.titleKey, systemImage: tab.systemImage, value: tab) {
                        tabStack(for: tab)
                    }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .environment(\.boardModalOverlayCoordinator, coordinator)

            // The overlay renders OUTSIDE the TabView so its own Resume / Close
            // stays live (#1019). `HoistedOverlayHost` — not this body — is what
            // observes the coordinator; see its doc for why that matters.
            HoistedOverlayHost(coordinator: coordinator)
        }
    }

    /// One tab's `NavigationStack`. `.navigationDestination(for:)` is attached
    /// to the stack's root content — not inside a `List`/`LazyVStack`/`ScrollView`
    /// row builder, where SwiftUI would only register it once the row is
    /// realized and value-based pushes would silently no-op.
    private func tabStack(for tab: AppTab) -> some View {
        let tabPath = path(tab)
        return NavigationStack(path: tabPath) {
            tabRoot(tab)
                .navigationDestination(for: Route.self) { route in
                    routeFactory.view(for: route, path: tabPath)
                }
        }
    }
}

// MARK: - HoistedOverlayHost

/// Renders the hoisted overlay, and is the ONLY view that observes the
/// coordinator.
///
/// SwiftUI's Observation registers a dependency against the body that actually
/// READS a property. Reading `coordinator.content` inside `RootShellView.body`
/// therefore re-ran that body — and on macOS `sidebarAdaptable`, re-running the
/// body that builds the `TabView` unmounts whatever is pushed in the selected
/// tab's `NavigationStack` (verified by bisection, #1020). Confining the read to
/// this leaf keeps the TabView subtree untouched when an overlay comes and goes.
private struct HoistedOverlayHost: View {
    let coordinator: BoardModalOverlayCoordinator

    var body: some View {
        if let hoisted = coordinator.content {
            hoisted.view
                .id(hoisted.id)
        }
    }
}
