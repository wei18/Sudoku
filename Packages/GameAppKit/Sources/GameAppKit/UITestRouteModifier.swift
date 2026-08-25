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
// `Route` enum (so this stays game-agnostic). `#if DEBUG`, a transparent no-op
// on every non-uitest launch, and effective on all platforms — macOS's detail
// column binds the SAME `path` array (see `GameShellUI.NavigationStackHost`),
// so pushing onto it lands on the production screen there too. Note the board
// routes still take each platform's normal presentation path from there: on
// iOS `GameRoot`'s `onPresentBoard` redirect lifts them into the
// `fullScreenCover`; on macOS (`onPresentBoard == nil`) they stay a plain push
// into the detail column — identical to what the hub's Start button produces.

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
        content.onAppear {
            guard let key = UITestLaunchArg.routeValue(),
                  let route = resolve(key) else { return }
            // Replace (not append) so a re-fired onAppear can't stack duplicates.
            rootViewModel.path = [route]
        }
    }
}

#endif
