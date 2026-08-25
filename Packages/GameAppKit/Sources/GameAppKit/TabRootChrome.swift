// TabRootChrome — the Settings gear every tab root carries (#1020).
//
// design.md §2.1 / §3.7: each tab pushes `.settings` from a trailing toolbar
// gear ("每 tab 右上齒輪"). This is not decoration — with HOME retired, its
// Settings card was the app's ONLY Settings entry point, so an interactive iPad
// pass over the new shell found Settings simply unreachable. On iPhone the gear
// is still the only way in; on iPad/macOS it sits alongside the sidebar.
//
// Applied to all three tab roots from one place (see `chromedTabRoots`) rather
// than by each game's own tab views: the two apps must not be able to drift on
// whether a given tab has the gear, which is exactly the per-app-wrapper drift
// the mirror principle exists to prevent.
//
// The push goes to the SELECTED tab's stack via `GameRootViewModel.push`, which
// is by construction the tab whose gear was tapped — so Settings pushes WITHIN
// the initiating tab and Back returns there, per §2.1's diagram (each tab owns
// its own path). No tab switch, no shared modal.

public import SwiftUI
internal import GameShellUI

// MARK: - TabRootChrome

public struct TabRootChrome<Route: Hashable & Sendable>: ViewModifier {
    private let rootViewModel: GameRootViewModel<Route>
    private let settingsRoute: Route

    public init(rootViewModel: GameRootViewModel<Route>, settingsRoute: Route) {
        self.rootViewModel = rootViewModel
        self.settingsRoute = settingsRoute
    }

    public func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: openSettings) {
                        // `Label` (not a bare `Image`) so the control keeps an
                        // accessible name; the toolbar renders icon-only.
                        Label("Settings", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("game.tab.settings")
                }
            }
    }

    /// The gear's action, factored out of the `Button` so the push contract is
    /// unit-testable without rendering a toolbar.
    @MainActor
    func openSettings() {
        rootViewModel.push(settingsRoute)
    }
}

// MARK: - View.tabRootChrome

extension View {
    /// Attach the shared Settings gear. Applied once per tab root at
    /// composition time — see `chromedTabRoots`.
    ///
    /// Must sit INSIDE the tab's `NavigationStack` (i.e. on the stack's root
    /// content, which is where `RootShellView` mounts `tabRoot(_:)`) — a
    /// `.toolbar` attached outside the stack has no navigation bar to render
    /// into and silently disappears.
    public func tabRootChrome<Route: Hashable & Sendable>(
        rootViewModel: GameRootViewModel<Route>,
        settingsRoute: Route
    ) -> ModifiedContent<Self, TabRootChrome<Route>> {
        modifier(TabRootChrome(rootViewModel: rootViewModel, settingsRoute: settingsRoute))
    }
}
