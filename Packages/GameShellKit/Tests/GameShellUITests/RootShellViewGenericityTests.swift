import SwiftUI
import Testing
@testable import GameShellUI

// MARK: - Sentinel: RootShellView stays generic
//
// PR X3 extracted RootShellView out of SudokuKit and genericized it over a
// `Route: Hashable` parameter (was hardcoded to `AppRoute` via the inline
// shell shape in `SudokuUI.RootView`). This test pins the genericity by
// instantiating the shell with a non-Sudoku Route type. Compile-time only —
// if a future refactor re-hardcodes a specific Route into the shell, this
// file stops compiling.
//
// Mirrors the sentinel established by `NavigationStackHostGenericityTests`
// in PR X1: SudokuKit's snapshot tests over RootView cover the Sudoku-Route
// path; this fixture covers the "is it actually generic" property they
// cannot.

// `SentinelRoute` + `SentinelFactory` are at file scope (not nested under
// the suite) so SwiftLint's `nesting` rule — "types nested at most 1 level
// deep" — is satisfied. The factory's `typealias Route = SentinelRoute`
// would otherwise sit at depth 2 (suite → factory → typealias) and trip
// the rule.

private enum SentinelRoute: Hashable {
    case first
    case second(payload: Int)
}

private struct SentinelFactory: RouteFactory {
    typealias Route = SentinelRoute

    @MainActor
    func view(for route: SentinelRoute, path: Binding<[SentinelRoute]>?) -> AnyView {
        AnyView(Text("destination"))
    }
}

@Suite("GameShellUI — RootShellView stays generic")
struct RootShellViewGenericityTests {
    @Test @MainActor func instantiatesWithNonSudokuRoute() {
        let shell = RootShellView<SentinelRoute, EmptyView>(
            path: .constant([.first]),
            title: "Sentinel",
            sidebarItems: [
                SidebarItem(
                    id: "first",
                    titleKey: "First",
                    systemImage: "1.circle",
                    onTap: {}
                )
            ],
            routeFactory: SentinelFactory(),
            rootContent: { EmptyView() }
        )
        _ = shell
    }
}
