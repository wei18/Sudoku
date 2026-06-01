// NavigationStackHost — compact/regular split-view container.
//
// iPhone (compact size class): wraps content in a `NavigationStack` bound to
// the supplied path. macOS / iPad regular: uses a `NavigationSplitView` with
// a thin sidebar selecting between top-level destinations.
//
// Destination resolution lives in the caller's `destination:` closure — this
// host only owns the *shape* of navigation, not the per-route content.
//
// Extracted from `SudokuKit/SudokuUI` (PR X1) so MinesweeperKit + a future
// third game's Kit can host the same nav shape with their own `Route` enums.
// Generic over `Route: Hashable` — any `Codable`/`Sendable` constraints needed
// for serialization remain the caller's concern.

public import SwiftUI

public struct NavigationStackHost<Route: Hashable, Sidebar: View, Content: View, Destination: View>: View {
    @Binding private var path: [Route]
    @Environment(\.horizontalSizeClass) private var sizeClass

    private let sidebar: () -> Sidebar
    private let content: () -> Content
    private let destination: (Route) -> Destination

    public init(
        path: Binding<[Route]>,
        @ViewBuilder sidebar: @escaping () -> Sidebar,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder destination: @escaping (Route) -> Destination
    ) {
        self._path = path
        self.sidebar = sidebar
        self.content = content
        self.destination = destination
    }

    public var body: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                sidebar()
            } detail: {
                NavigationStack(path: $path) {
                    content()
                        .navigationDestination(for: Route.self, destination: destination)
                }
            }
        } else {
            NavigationStack(path: $path) {
                content()
                    .navigationDestination(for: Route.self, destination: destination)
            }
        }
    }
}
