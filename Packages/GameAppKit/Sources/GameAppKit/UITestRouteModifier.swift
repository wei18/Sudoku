// UITestRouteModifier — DEBUG-only deep-link hook (#510).
//
// Reads the `-uitest-route <key>` launch argument and puts the shell on the
// matching screen, so a reviewer / XCUITest reaches it in ONE launch instead of
// tapping through the app. Board + completion stay on the near-win hooks (those
// need a constructed engine board).
//
// #1020: the argument's keys did not all survive the tab rewrite. `daily` and
// `practice` used to be ROUTES a test could push; they are tab identities now
// (`AppTab.today` / `.practice`), while `settings` is still a push. A closure
// returning `Route?` can no longer express both, so the seam resolves into
// `UITestLaunchTarget` instead — one value type covering "select this tab" and
// "select this tab, then push this route onto it". The launch-argument key
// string itself is unchanged, so existing E2E invocations keep working.
//
// Applied at the app's root view, ALONGSIDE the per-app near-win modifiers, with
// the app supplying the `resolve` closure that maps a key → its own target (so
// this stays game-agnostic). Mirrors the near-win modifier pattern: iOS-only,
// `#if DEBUG`, a transparent no-op on every non-uitest launch.

#if DEBUG

public import SwiftUI
public import GameShellUI

// MARK: - UITestLaunchTarget

/// Where a `-uitest-route` key lands.
///
/// Both cases carry a tab because every screen now lives inside one: a push
/// with no tab selected would land on a stack the runner cannot see.
public enum UITestLaunchTarget<Route: Hashable & Sendable>: Sendable {
    /// Select a tab and stop there — the landing for keys that used to be
    /// root-level routes (`daily` → `.today`, `practice` → `.practice`).
    case tab(AppTab)
    /// Select `tab`, then push `route` onto that tab's stack.
    case push(Route, tab: AppTab)

    /// Push onto the tab the app opens on, so the screen is visible immediately.
    public static func push(_ route: Route) -> Self { .push(route, tab: .today) }
}

// MARK: - UITestRouteModifier

public struct UITestRouteModifier<Route: Hashable & Sendable>: ViewModifier {
    private let rootViewModel: GameRootViewModel<Route>
    private let resolve: (String) -> UITestLaunchTarget<Route>?

    /// - Parameters:
    ///   - rootViewModel: the LIVE root VM whose selected tab + per-tab paths
    ///     drive the real shell — so the deep-link lands on the production
    ///     screen, not a parallel test-only one.
    ///   - resolve: maps a screen key (e.g. `"settings"`, `"daily"`) to this
    ///     app's target, or `nil` for keys this app doesn't deep-link.
    public init(
        rootViewModel: GameRootViewModel<Route>,
        resolve: @escaping (String) -> UITestLaunchTarget<Route>?
    ) {
        self.rootViewModel = rootViewModel
        self.resolve = resolve
    }

    public func body(content: Content) -> some View {
        #if os(iOS)
        content.onAppear {
            guard let key = UITestLaunchArg.routeValue(),
                  let target = resolve(key) else { return }
            apply(target)
        }
        #else
        content
        #endif
    }

    /// The deep-link's effect, factored out of `body` so it is unit-testable
    /// without rendering — and so the "replace, never append" property below
    /// stays pinned by a test rather than by a comment.
    @MainActor
    func apply(_ target: UITestLaunchTarget<Route>) {
        switch target {
        case let .tab(tab):
            rootViewModel.selectedTab = tab
        case let .push(route, tab):
            rootViewModel.selectedTab = tab
            // Replace (not append) so a re-fired onAppear can't stack duplicates.
            rootViewModel.setPath([route], for: tab)
        }
    }
}

#endif
