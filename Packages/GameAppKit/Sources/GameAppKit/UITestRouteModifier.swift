// UITestRouteModifier — DEBUG-only deep-link hook (#510).
//
// Reads the `-uitest-route <key>` launch argument and pushes the matching
// `Route` onto the live `GameRootViewModel.path`, so a reviewer / XCUITest
// reaches a screen (daily / practice / settings) in ONE launch instead of
// tapping through the home stack. Board + completion stay on the near-win
// hooks (those need a constructed engine board).
//
// Applied at the app's root view, ALONGSIDE the per-app near-win modifiers, with
// the app supplying a `resolve` closure that maps the screen key → its own
// `Route` enum (so this stays game-agnostic). Mirrors the near-win modifier
// pattern: iOS-only, `#if DEBUG`, a transparent no-op on every non-uitest launch.

#if DEBUG

public import SwiftUI

public struct UITestRouteModifier<Route: Hashable & Sendable>: ViewModifier {
    private let rootViewModel: GameRootViewModel<Route>
    private let resolve: (String) -> Route?

    /// - Parameters:
    ///   - rootViewModel: the LIVE root VM whose `path` drives the real
    ///     `NavigationStack` — so the deep-link lands on the production screen.
    ///   - resolve: maps a screen key (e.g. `"settings"`) to this app's `Route`,
    ///     or nil for keys this app doesn't deep-link (incl. `"home"` = root).
    public init(
        rootViewModel: GameRootViewModel<Route>,
        resolve: @escaping (String) -> Route?
    ) {
        self.rootViewModel = rootViewModel
        self.resolve = resolve
    }

    public func body(content: Content) -> some View {
        #if os(iOS)
        content.onAppear {
            guard let key = UITestLaunchArg.routeValue(),
                  let route = resolve(key) else { return }
            // Replace (not append) so a re-fired onAppear can't stack duplicates.
            rootViewModel.path = [route]
        }
        #else
        content
        #endif
    }
}

#endif
