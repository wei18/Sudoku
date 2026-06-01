import SwiftUI
import Testing
@testable import GameShellUI

// MARK: - Sentinel: NavigationStackHost stays generic
//
// PR X1 extracted NavigationStackHost out of SudokuKit and genericized its
// path / destination over a `Route: Hashable` parameter (was hardcoded to
// `AppRoute`). This test pins the genericity by instantiating the host with
// a non-Sudoku Route type. Compile-time only — if a future refactor
// re-hardcodes a specific Route into the host, this file stops compiling.
//
// SudokuKit's existing snapshot tests over RootView verify the Sudoku-Route
// path; this fixture covers the "is it actually generic" property they
// cannot.

@Suite("GameShellUI — NavigationStackHost stays generic")
struct NavigationStackHostGenericityTests {
    private enum SentinelRoute: Hashable {
        case first
        case second(payload: Int)
    }

    @Test @MainActor func instantiatesWithNonSudokuRoute() {
        let host = NavigationStackHost<SentinelRoute, EmptyView, Text, Text>(
            path: .constant([.first]),
            sidebar: { EmptyView() },
            content: { Text("content") },
            destination: { _ in Text("destination") }
        )
        _ = host
    }
}
