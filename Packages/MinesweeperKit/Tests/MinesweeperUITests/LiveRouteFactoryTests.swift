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
        var path: [AppRoute] = [.board(difficulty: .beginner, seed: 0, mode: .practice)]
        let binding = Binding<[AppRoute]>(
            get: { path },
            set: { path = $0 }
        )
        let view = factory.view(for: .board(difficulty: .beginner, seed: 42, mode: .daily), path: binding)
        _ = view
    }

    @Test func factoryReturnsViewForSettingsRoute() {
        let factory = LiveRouteFactory()
        let view = factory.view(for: .settings, path: nil)
        _ = view
    }

    // #288 / #289: the Home mode cards push these routes. Sentinel coverage —
    // a future switch refactor that drops a case fails compilation here.

    @Test func factoryReturnsViewForDailyRoute() {
        let factory = LiveRouteFactory()
        var path: [AppRoute] = []
        let binding = Binding<[AppRoute]>(get: { path }, set: { path = $0 })
        let view = factory.view(for: .daily, path: binding)
        _ = view
    }

    @Test func factoryReturnsViewForPracticeRoute() {
        let factory = LiveRouteFactory()
        var path: [AppRoute] = []
        let binding = Binding<[AppRoute]>(get: { path }, set: { path = $0 })
        let view = factory.view(for: .practice, path: binding)
        _ = view
    }

    @Test func factoryHandlesNilBindingForHubRoutes() {
        // Hub routes fall back to `.constant([])` when no binding is supplied
        // (preview path); must not trap.
        let factory = LiveRouteFactory()
        _ = factory.view(for: .daily, path: nil)
        _ = factory.view(for: .practice, path: nil)
    }

    // #386: the solved-daily re-view route renders the standalone Completion
    // surface. Sentinel — a future switch refactor dropping the case fails here.
    @Test func factoryReturnsViewForCompletionRoute() {
        let factory = LiveRouteFactory()
        var path: [AppRoute] = []
        let binding = Binding<[AppRoute]>(get: { path }, set: { path = $0 })
        let view = factory.view(for: .completion(difficulty: .beginner, mode: .daily), path: binding)
        _ = view
    }

    @Test func factoryHandlesAllDifficultyCasesForCompletion() {
        let factory = LiveRouteFactory()
        for difficulty in Difficulty.allCases {
            let view = factory.view(for: .completion(difficulty: difficulty, mode: .daily))
            _ = view
        }
    }

    @Test func factoryHandlesAllDifficultyCases() {
        let factory = LiveRouteFactory()
        for difficulty in Difficulty.allCases {
            let view = factory.view(for: .board(difficulty: difficulty, seed: 1, mode: .practice))
            _ = view
        }
    }

    // MARK: - #491 modal vs push context

    /// #491: with `onPresentBoard` wired, calling `view(for:path:nil)` (the modal
    /// path used by GameRoot's fullScreenCover) must return the real board view,
    /// not the zero-content `GameBoardRedirect`.
    @Test func boardRouteWithOnPresentBoardAndNilPathReturnsBoardView() {
        var presented: AppRoute?
        let factory = LiveRouteFactory(onPresentBoard: { presented = $0 })
        let view = factory.view(for: .board(difficulty: .beginner, seed: 42, mode: .practice), path: nil)
        let dump = String(describing: view)
        // Modal context (path: nil) must render the real board, not the redirect.
        #expect(dump.contains("MinesweeperBoardView"), "Expected MinesweeperBoardView but got: \(dump)")
        // onPresentBoard must NOT have been invoked from this factory call.
        #expect(presented == nil)
    }

    /// #491: with `onPresentBoard` wired, calling `view(for:path:<non-nil>)` (the
    /// push context) must still return `GameBoardRedirect`.
    @Test func boardRouteWithOnPresentBoardAndNonNilPathReturnsRedirect() {
        var path: [AppRoute] = [.board(difficulty: .beginner, seed: 42, mode: .practice)]
        let binding = Binding<[AppRoute]>(get: { path }, set: { path = $0 })
        let factory = LiveRouteFactory(onPresentBoard: { _ in })
        let view = factory.view(for: .board(difficulty: .beginner, seed: 42, mode: .practice), path: binding)
        let dump = String(describing: view)
        #expect(dump.contains("GameBoardRedirect"), "Expected GameBoardRedirect but got: \(dump)")
    }

    /// #491: `.resumeBoard` — same two-context contract. path: nil → real loader.
    @Test func resumeBoardWithOnPresentBoardAndNilPathReturnsEmptyView() {
        // Without a savedGameStore the loader falls back to EmptyView (documented
        // fallback); the key assertion is that it does NOT return GameBoardRedirect.
        let factory = LiveRouteFactory(onPresentBoard: { _ in })
        let view = factory.view(for: .resumeBoard(recordName: "ms-daily-2026-06-12", mode: .daily), path: nil)
        let dump = String(describing: view)
        #expect(!dump.contains("GameBoardRedirect"), "path: nil must not produce GameBoardRedirect; got: \(dump)")
    }

    /// #491: `.resumeBoard` push context → redirect still fires.
    @Test func resumeBoardWithOnPresentBoardAndNonNilPathReturnsRedirect() {
        var path: [AppRoute] = [.resumeBoard(recordName: "ms-daily-2026-06-12", mode: .daily)]
        let binding = Binding<[AppRoute]>(get: { path }, set: { path = $0 })
        let factory = LiveRouteFactory(onPresentBoard: { _ in })
        let view = factory.view(for: .resumeBoard(recordName: "ms-daily-2026-06-12", mode: .daily), path: binding)
        let dump = String(describing: view)
        #expect(dump.contains("GameBoardRedirect"), "Expected GameBoardRedirect but got: \(dump)")
    }

    // MARK: - popToNewGame

    @Test func popToNewGameEmptiesPath() {
        var path: [AppRoute] = [.board(difficulty: .beginner, seed: 1, mode: .practice)]
        let binding = Binding<[AppRoute]>(get: { path }, set: { path = $0 })
        LiveRouteFactory.popToNewGame(path: binding)
        #expect(path.isEmpty)
    }

    @Test func popToNewGameOnDeepPathStillEmpties() {
        var path: [AppRoute] = [.settings, .board(difficulty: .expert, seed: 42, mode: .practice)]
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
