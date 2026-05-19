// NavigationStackHost — compact/regular split-view container.
//
// iPhone (compact size class): wraps content in a `NavigationStack` bound to
// the supplied path. macOS / iPad regular: uses a `NavigationSplitView` with
// a thin sidebar selecting between the four top-level destinations.
//
// Destination resolution lives in `routeView(_:)` of the caller — this host
// only owns the *shape* of navigation, not the per-route content.

public import SwiftUI

public struct NavigationStackHost<Sidebar: View, Content: View, Destination: View>: View {
    @Binding private var path: [AppRoute]
    @Environment(\.horizontalSizeClass) private var sizeClass

    private let sidebar: () -> Sidebar
    private let content: () -> Content
    private let destination: (AppRoute) -> Destination

    public init(
        path: Binding<[AppRoute]>,
        @ViewBuilder sidebar: @escaping () -> Sidebar,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder destination: @escaping (AppRoute) -> Destination
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
                        .navigationDestination(for: AppRoute.self, destination: destination)
                }
            }
        } else {
            NavigationStack(path: $path) {
                content()
                    .navigationDestination(for: AppRoute.self, destination: destination)
            }
        }
    }
}
