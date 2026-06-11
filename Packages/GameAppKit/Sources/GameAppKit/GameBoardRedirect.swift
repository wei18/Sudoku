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
                // Pop this redirect entry from the navigation stack, then
                // present the game as a fullScreenCover. Both happen on
                // MainActor without a Task to avoid a frame gap.
                if var current = path?.wrappedValue, !current.isEmpty {
                    current.removeLast()
                    path?.wrappedValue = current
                }
                onPresent(route)
            }
    }
}
