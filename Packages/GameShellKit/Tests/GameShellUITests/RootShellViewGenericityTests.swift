import SwiftUI
import Testing
@testable import GameShellUI

// MARK: - Sentinel: RootShellView stays generic
//
// PR X3 extracted RootShellView out of SudokuKit and genericized it over a
// `Route: Hashable` parameter. #1020 rewrote it as a 3-tab `sidebarAdaptable`
// TabView with one path per tab, but the genericity property is unchanged and
// still worth pinning: instantiate the shell with a non-Sudoku Route type.
// Compile-time only — if a future refactor re-hardcodes a specific Route into
// the shell, this file stops compiling.
//
// The per-tab `path:` closure is the other half of the #1020 contract: the
// shell must accept a DIFFERENT binding per `AppTab` (design.md §2.1 — finishing
// a game in Practice must not tear down Today's stack), so the sentinel wires
// three separate storages and asserts the shell takes them.

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
        let shell = RootShellView<SentinelRoute, Text>(
            selectedTab: .constant(.today),
            path: { _ in .constant([.first]) },
            routeFactory: SentinelFactory(),
            tabRoot: { tab in Text(tab.rawValue) }
        )
        _ = shell
    }

    /// Each tab must be able to hand the shell a DIFFERENT path binding — the
    /// per-tab-stack property #1020 exists for. Pinned by wiring three distinct
    /// storages and reading them back through the same closure the shell calls.
    @Test @MainActor func perTabPathClosureResolvesADistinctBindingPerTab() {
        var storage: [AppTab: [SentinelRoute]] = [
            .today: [.first],
            .practice: [.second(payload: 2)],
            .progress: []
        ]
        let path: (AppTab) -> Binding<[SentinelRoute]> = { tab in
            Binding(
                get: { storage[tab] ?? [] },
                set: { storage[tab] = $0 }
            )
        }

        let shell = RootShellView<SentinelRoute, Text>(
            selectedTab: .constant(.practice),
            path: path,
            routeFactory: SentinelFactory(),
            tabRoot: { tab in Text(tab.rawValue) }
        )
        _ = shell

        #expect(path(.today).wrappedValue == [.first])
        #expect(path(.practice).wrappedValue == [.second(payload: 2)])
        #expect(path(.progress).wrappedValue.isEmpty)

        // Writing through one tab's binding must not disturb another's.
        path(.progress).wrappedValue = [.first]
        #expect(storage[.progress] == [.first])
        #expect(storage[.today] == [.first])
        #expect(storage[.practice] == [.second(payload: 2)])
    }
}
