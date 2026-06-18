// BoardDestinationTests — #559 / #491 contract for the shared boardDestination helper.
//
// Two invariants:
//   1. Redirect path: onPresentBoard non-nil AND path non-nil → GameBoardRedirect.
//   2. Inline path:   onPresentBoard nil OR path nil              → buildInline result.
//
// These mirror the per-game #491 tests already in RouteFactoryTests (SudokuKit)
// and LiveRouteFactoryTests (MinesweeperKit) but exercise the shared decision
// point once, centrally, so future regressions surface here regardless of
// which factory calls it.

import SwiftUI
import Testing
@testable import GameAppKit

// A minimal Hashable+Sendable route type for the generic helper tests.
private enum TestRoute: Hashable, Sendable {
    case board
}

@MainActor
@Suite("boardDestination — #491 redirect-vs-inline contract")
struct BoardDestinationTests {

    private let sentinelView = AnyView(Color.red)

    // MARK: - Redirect path

    /// Both onPresentBoard and path non-nil → GameBoardRedirect returned.
    @Test func redirectsWhenBothOnPresentBoardAndPathAreNonNil() {
        var path: [TestRoute] = [.board]
        let binding = Binding<[TestRoute]>(get: { path }, set: { path = $0 })
        let view = boardDestination(
            route: TestRoute.board,
            path: binding,
            onPresentBoard: { _ in },
            buildInline: { self.sentinelView }
        )
        let dump = String(describing: view)
        #expect(
            dump.contains("GameBoardRedirect"),
            "Expected GameBoardRedirect but got: \(dump)"
        )
    }

    // MARK: - Inline path

    /// onPresentBoard nil, path non-nil → buildInline result returned.
    @Test func inlineWhenOnPresentBoardIsNil() {
        var path: [TestRoute] = [.board]
        let binding = Binding<[TestRoute]>(get: { path }, set: { path = $0 })
        let view = boardDestination(
            route: TestRoute.board,
            path: binding,
            onPresentBoard: nil,
            buildInline: { AnyView(Color.green) }
        )
        let dump = String(describing: view)
        #expect(
            !dump.contains("GameBoardRedirect"),
            "Expected inline result but got redirect: \(dump)"
        )
    }

    /// onPresentBoard non-nil, path nil (modal context) → buildInline result returned.
    /// This is the #491 key invariant: the redirect must NOT fire in modal context
    /// or the modal renders Color.clear (blank screen).
    @Test func inlineWhenPathIsNil() {
        let view = boardDestination(
            route: TestRoute.board,
            path: nil,
            onPresentBoard: { _ in },
            buildInline: { AnyView(Color.blue) }
        )
        let dump = String(describing: view)
        #expect(
            !dump.contains("GameBoardRedirect"),
            "Modal context (path: nil) must not produce GameBoardRedirect; got: \(dump)"
        )
    }

    /// Both nil → buildInline result returned (legacy push-only path, tests/previews).
    @Test func inlineWhenBothAreNil() {
        let view = boardDestination(
            route: TestRoute.board,
            path: nil,
            onPresentBoard: nil,
            buildInline: { AnyView(Color.yellow) }
        )
        let dump = String(describing: view)
        #expect(
            !dump.contains("GameBoardRedirect"),
            "Both nil must produce inline result; got: \(dump)"
        )
    }

    /// buildInline is not called when the redirect path fires.
    @Test func buildInlineNotCalledOnRedirectPath() {
        var called = false
        var path: [TestRoute] = [.board]
        let binding = Binding<[TestRoute]>(get: { path }, set: { path = $0 })
        _ = boardDestination(
            route: TestRoute.board,
            path: binding,
            onPresentBoard: { _ in },
            buildInline: {
                called = true
                return AnyView(EmptyView())
            }
        )
        #expect(!called, "buildInline must not be evaluated on the redirect path")
    }
}
