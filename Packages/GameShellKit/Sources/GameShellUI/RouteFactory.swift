// RouteFactory — game-agnostic navigation seam.
//
// Owned by GameShellKit so SudokuKit, MinesweeperKit, and a future third
// game's Kit can share the same destination-construction contract while
// each plugs in its own concrete factory + Route enum.
//
// Generic via primary associated type `Route: Hashable` — callers store
// instances as `any RouteFactory<TheirRouteEnum>`. Hashable is the minimum
// SwiftUI's `.navigationDestination(for:)` requires; Sendable / Codable
// remain the concrete factory's concern.
//
// §設計決定: `view(for:path:) -> AnyView`
//   AnyView pays a small SwiftUI diff cost (identity-via-AnyView erasure) but
//   keeps the protocol non-generic over Destination so we can store it as
//   `any RouteFactory<Route>` without forcing every host (RootView, tests)
//   to be generic over the factory's destination type. SwiftUI itself uses
//   AnyView in `.navigationDestination` API closures — not breaking new
//   ground.

public import SwiftUI

// MARK: - RouteFactory

public protocol RouteFactory<Route>: Sendable {
    associatedtype Route: Hashable

    /// - Parameter path: optional binding to the host `NavigationStack`'s
    ///   path so destination view-models that drive further pushes write
    ///   into the same array the stack observes. `nil` falls back to a
    ///   local stub array so tests / previews can call this without wiring
    ///   a binding.
    @MainActor
    func view(for route: Route, path: Binding<[Route]>?) -> AnyView
}

extension RouteFactory {
    /// Test / preview convenience — call sites that don't need to drive a
    /// real navigation stack can omit the binding.
    @MainActor
    public func view(for route: Route) -> AnyView {
        view(for: route, path: nil)
    }
}
