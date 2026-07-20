// GameBoardRedirect — zero-content destination that immediately pops itself
// and instead triggers a fullScreenCover presentation via the supplied
// `onPresent` closure.
//
// SDD-003 Epic 1: board routes used to be NavigationStack pushes. They are
// now fullScreenCover modals (R1.1). Hub VMs still call `path.append(.board(...))`
// — touching all hub VMs is a larger, riskier change. Instead, `LiveRouteFactory`
// returns this redirect view for board routes: it fires `onPresent()` (which
// calls `GameRootViewModel.presentGame(route:)`) then removes the route from the
// navigation path, producing a seamless transition from push to modal.
//
// The `path` binding passed by `NavigationStackHost` is the root path; clearing
// the last entry returns the stack to Home while the fullScreenCover appears on top.

public import SwiftUI

// MARK: - boardDestination helper

/// Shared #491 two-context board-redirect decision.
///
/// Every game's `RouteFactory.view(for:path:)` board cases share the same
/// guard: when `onPresentBoard` is wired AND the route arrived via a
/// NavigationStack push (`path != nil`), return a `GameBoardRedirect` that
/// pops the stack entry and presents the board as a fullScreenCover modal.
/// In the modal context (`path == nil`) GameRoot calls `view(for:path:nil)` to
/// build the real board view — the redirect must NOT fire or the modal renders
/// `Color.clear` (blank screen). The legacy push path (`onPresentBoard == nil`)
/// falls straight through to `buildInline` for tests / previews.
///
/// Centralising the decision here means a future fix to the contract is
/// one edit, not one per game.
@MainActor
public func boardDestination<Route: Hashable & Sendable>(
    route: Route,
    path: Binding<[Route]>?,
    onPresentBoard: (@MainActor (Route) -> Void)?,
    buildInline: () -> AnyView
) -> AnyView {
    if let onPresentBoard, path != nil {
        return AnyView(
            GameBoardRedirect(
                route: route,
                path: path,
                onPresent: onPresentBoard
            )
        )
    }
    return buildInline()
}

// MARK: - GameBoardRedirect

@MainActor
public struct GameBoardRedirect<Route: Hashable & Sendable>: View {
    private let route: Route
    private let path: Binding<[Route]>?
    private let onPresent: @MainActor (Route) -> Void

    public init(
        route: Route,
        path: Binding<[Route]>?,
        onPresent: @escaping @MainActor (Route) -> Void
    ) {
        self.route = route
        self.path = path
        self.onPresent = onPresent
    }

    public var body: some View {
        Color.clear
            .onAppear {
                // Present the game as a fullScreenCover, THEN pop this
                // redirect entry from the navigation stack. Both happen on
                // MainActor without a Task to avoid a frame gap — SwiftUI
                // coalesces both state mutations into the same re-render
                // regardless of order, so this ordering has no visual cost.
                //
                // #912: the order matters for correctness, not just visuals.
                // `GameRoot`'s `path`-shrink branch (`handlePathShrink`)
                // reads `GameRootViewModel.isGamePresented` to distinguish
                // this synthetic board-OPEN pop from a genuine session-end
                // close. `onPresent` (→ `presentGame(route:)`) must flip
                // `isGamePresented` to `true` BEFORE the pop below fires the
                // path-shrink branch, or that branch would see
                // `isGamePresented == false` and wrongly treat this open-time
                // pop as a close.
                onPresent(route)
                if var current = path?.wrappedValue, !current.isEmpty {
                    current.removeLast()
                    path?.wrappedValue = current
                }
            }
    }
}
