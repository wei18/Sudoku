// LiveRouteFactoryTests — sentinel coverage for Minesweeper's concrete
// `RouteFactory<AppRoute>`. Mirrors the GameShellKit sentinel-test pattern:
// instantiate + invoke `view(for:)` so a future refactor that breaks the
// switch or the protocol conformance fails compilation / at-test-time.
//
// AnyView's payload isn't introspectable without snapshot infra — coverage
// is "factory constructs without crashing for every case", not pixel parity.

import SwiftUI
import Testing
@testable import MinesweeperAppComposition
import MinesweeperUI
import MinesweeperEngine
import GameShellUI

@MainActor
@Suite struct LiveRouteFactoryTests {

    @Test func factoryReturnsViewForBoardRoute() {
        let factory = LiveRouteFactory()
        var path: [AppRoute] = [.board(difficulty: .beginner, seed: 0)]
        let binding = Binding<[AppRoute]>(
            get: { path },
            set: { path = $0 }
        )
        let view = factory.view(for: .board(difficulty: .beginner, seed: 42), path: binding)
        _ = view
    }

    @Test func factoryReturnsViewForSettingsRoute() {
        let factory = LiveRouteFactory()
        let view = factory.view(for: .settings, path: nil)
        _ = view
    }

    @Test func factoryHandlesAllDifficultyCases() {
        let factory = LiveRouteFactory()
        for difficulty in Difficulty.allCases {
            let view = factory.view(for: .board(difficulty: difficulty, seed: 1))
            _ = view
        }
    }

    // MARK: - popToNewGame

    @Test func popToNewGameEmptiesPath() {
        var path: [AppRoute] = [.board(difficulty: .beginner, seed: 1)]
        let binding = Binding<[AppRoute]>(get: { path }, set: { path = $0 })
        LiveRouteFactory.popToNewGame(path: binding)
        #expect(path.isEmpty)
    }

    @Test func popToNewGameOnDeepPathStillEmpties() {
        var path: [AppRoute] = [.settings, .board(difficulty: .expert, seed: 42)]
        let binding = Binding<[AppRoute]>(get: { path }, set: { path = $0 })
        LiveRouteFactory.popToNewGame(path: binding)
        #expect(path.isEmpty)
    }

    @Test func popToNewGameOnEmptyPathIsNoop() {
        var path: [AppRoute] = []
        let binding = Binding<[AppRoute]>(get: { path }, set: { path = $0 })
        LiveRouteFactory.popToNewGame(path: binding)
        #expect(path.isEmpty)
    }

    @Test func popToNewGameWithNilBindingIsNoop() {
        // Must not trap when the toolbar receives no binding (e.g. preview).
        LiveRouteFactory.popToNewGame(path: nil)
    }
}
