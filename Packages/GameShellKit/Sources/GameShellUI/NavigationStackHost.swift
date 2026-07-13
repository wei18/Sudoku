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
    #if os(macOS)
    // #763: true while a pushed board's pause/completion overlay is up —
    // masks the sidebar for the overlay's duration. See
    // ModalOverlayPreference.swift for why iOS/iPadOS don't need this (their
    // board is a fullScreenCover, which already covers the sidebar).
    @State private var modalOverlayActive = false
    #endif

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
                    #if os(macOS)
                    // #763: while a pushed board's overlay is active, the
                    // sidebar must stop being a live navigation surface —
                    // `.disabled` blocks taps, the scrim signals it visually.
                    // iOS/iPadOS keep the unmodified sidebar (their board
                    // never reaches this branch's bug — see
                    // ModalOverlayPreference.swift).
                    .disabled(modalOverlayActive)
                    .overlay {
                        if modalOverlayActive {
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .ignoresSafeArea()
                                .accessibilityHidden(true)
                        }
                    }
                    #endif
            } detail: {
                NavigationStack(path: $path) {
                    content()
                        .navigationDestination(for: Route.self, destination: destination)
                }
            }
            #if os(macOS)
            .onPreferenceChange(ModalOverlayActiveKey.self) { modalOverlayActive = $0 }
            #endif
        } else {
            NavigationStack(path: $path) {
                content()
                    .navigationDestination(for: Route.self, destination: destination)
            }
        }
    }
}
