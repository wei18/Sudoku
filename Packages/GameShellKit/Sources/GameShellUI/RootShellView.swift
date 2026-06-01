// RootShellView — generic app root container.
//
// Owns the `NavigationStackHost` shape, mounts a caller-supplied root
// content view, and renders a config-driven sidebar (regular-size-class).
// Per-route destinations are resolved through the supplied `RouteFactory`.
//
// Extracted from `SudokuKit/SudokuUI/Root/RootView.swift` (PR X3) so
// MinesweeperKit + a future third game's Kit consume the same shell.
// Sudoku-specific bits (ResumePill / HomeView / bootstrap / theme background /
// toast overlay) stay in `SudokuKit.RootView`, which now delegates here.

public import SwiftUI

public struct RootShellView<Route: Hashable, RootContent: View>: View {
    @Binding private var path: [Route]
    private let title: LocalizedStringKey
    private let sidebarItems: [SidebarItem<Route>]
    private let routeFactory: any RouteFactory<Route>
    private let rootContent: () -> RootContent

    public init(
        path: Binding<[Route]>,
        title: LocalizedStringKey,
        sidebarItems: [SidebarItem<Route>],
        routeFactory: any RouteFactory<Route>,
        @ViewBuilder rootContent: @escaping () -> RootContent
    ) {
        self._path = path
        self.title = title
        self.sidebarItems = sidebarItems
        self.routeFactory = routeFactory
        self.rootContent = rootContent
    }

    public var body: some View {
        NavigationStackHost(
            path: $path,
            sidebar: { sidebarList },
            content: rootContent,
            destination: { route in
                routeFactory.view(for: route, path: $path)
            }
        )
    }

    // Sidebar mirrors the caller's mode list. The shell does not know which
    // items push a route vs. which fire a side effect — that decision lives
    // in each item's `onTap` closure, supplied by the caller.
    //
    // Note (2026-05-23, carried forward from Sudoku's RootView): the
    // `.navigationDestination(for:)` lives inside the detail pane's
    // `NavigationStack` (see `NavigationStackHost`), which on macOS
    // `NavigationSplitView` is a separate scope from the sidebar's List.
    // SwiftUI's value-link lookup walks ancestors for a matching destination,
    // and the cross-pane scope makes value-based `NavigationLink(value:)`
    // fire inconsistently. Direct `path.append(...)` from the onTap closure
    // keeps mutation inside the same scope as the destination registry, so
    // the push is deterministic.
    @ViewBuilder
    private var sidebarList: some View {
        List {
            ForEach(sidebarItems) { item in
                Button(action: item.onTap) {
                    Label(item.titleKey, systemImage: item.systemImage)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(title)
    }
}
