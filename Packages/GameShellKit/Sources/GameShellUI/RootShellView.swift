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
// #763 / #1019 — pause & completion must lock the whole shell:
// `.disabled(isBoardModalOverlayActive)` covers the ENTIRE TabView (sidebar rows
// + tab-switch chrome + tab content) because `sidebarAdaptable` generates that
// chrome itself and leaves nothing narrower to scope to. The overlay therefore
// cannot render inside that subtree — its own Resume / Close button would be
// disabled too, deadlocking the player (#1019 spike evidence 01–04). Instead the
// overlay is rendered as a ZStack SIBLING of the TabView via
// `BoardModalOverlayCoordinator`, outside the `.disabled()` scope
// (evidence 06–10). See `BoardModalOverlayHoist.swift`.

public import SwiftUI

public struct RootShellView<Route: Hashable, TabRoot: View>: View {
    @Binding private var selectedTab: AppTab
    private let path: (AppTab) -> Binding<[Route]>
    private let routeFactory: any RouteFactory<Route>
    private let tabRoot: (AppTab) -> TabRoot

    // #763: true while a board's Pause/Completion overlay is up. Purely a mirror
    // of the child-published preference — never written anywhere else.
    @State private var isBoardModalOverlayActive = false

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
            // A board pushed into a tab's stack publishes this preference; it
            // propagates up here regardless of which tab or route is showing.
            .onPreferenceChange(BoardModalOverlayActivePreferenceKey.self) { isActive in
                isBoardModalOverlayActive = isActive
            }
            .disabled(isBoardModalOverlayActive)
            .environment(\.boardModalOverlayCoordinator, coordinator)

            // #1019: rendered OUTSIDE the `.disabled(…)` above so the overlay's
            // own CTA stays live. `.id` pins the presentation's identity so its
            // local `@State` survives for as long as it is up.
            if let hoisted = coordinator.content {
                hoisted.view
                    .id(hoisted.id)
            }
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
