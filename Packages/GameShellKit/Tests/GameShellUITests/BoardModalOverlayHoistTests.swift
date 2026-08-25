// BoardModalOverlayHoistTests — pins the #1019-adopted overlay-hoisting seam.
//
// What is unit-testable here is the seam's STATE contract: the coordinator's
// present/dismiss transitions, the per-presentation identity that keeps the
// hoisted view's own `@State` alive, and the environment key's `nil` default
// (which is what makes iOS `fullScreenCover` boards keep rendering in place).
//
// What is NOT unit-testable here is the rendered outcome — that a paused board
// leaves the sidebar/tab rows un-tappable while its own CTA stays live. That is
// exactly the property #1019's spike had to drive interactively (idb on iPad,
// XCUITest coordinate-clicks on macOS), and #1020 carries the same
// before-merge verification. See the issue's acceptance list.

import SwiftUI
import Testing
@testable import GameShellUI

@Suite("GameShellUI — BoardModalOverlayCoordinator")
@MainActor
struct BoardModalOverlayCoordinatorTests {

    @Test("starts with nothing hoisted")
    func startsEmpty() {
        #expect(BoardModalOverlayCoordinator().content == nil)
    }

    @Test("present registers the built view")
    func presentRegistersContent() {
        let coordinator = BoardModalOverlayCoordinator()

        coordinator.present { AnyView(Text("pause")) }

        #expect(coordinator.content != nil)
    }

    @Test("dismiss clears the hoisted overlay")
    func dismissClearsContent() {
        let coordinator = BoardModalOverlayCoordinator()
        coordinator.present { AnyView(Text("pause")) }

        coordinator.dismiss()

        #expect(coordinator.content == nil)
    }

    @Test("dismiss with nothing presented is a safe no-op")
    func dismissWhenEmptyIsNoOp() {
        let coordinator = BoardModalOverlayCoordinator()

        coordinator.dismiss()

        #expect(coordinator.content == nil)
    }

    /// Each presentation mints a fresh id. `RootShellView` pins the hoisted
    /// view's SwiftUI identity with `.id(hoisted.id)`, so a NEW presentation
    /// must be a new identity (fresh local `@State`) while a single
    /// presentation keeps one — the reason the modifier registers only on the
    /// `false → true` edge instead of on every render.
    @Test("each presentation gets a distinct identity")
    func presentationsHaveDistinctIdentities() {
        let coordinator = BoardModalOverlayCoordinator()

        coordinator.present { AnyView(Text("pause")) }
        let first = coordinator.content?.id
        coordinator.dismiss()
        coordinator.present { AnyView(Text("completion")) }
        let second = coordinator.content?.id

        #expect(first != nil)
        #expect(second != nil)
        #expect(first != second)
    }

    /// The overlay body must not be built while nothing is being presented —
    /// building it eagerly would read board state (and register observation)
    /// for an overlay that is not on screen.
    @Test("the content builder runs only when presenting")
    func contentBuilderIsNotRunEagerly() {
        let coordinator = BoardModalOverlayCoordinator()
        var buildCount = 0

        coordinator.dismiss()
        #expect(buildCount == 0)

        coordinator.present {
            buildCount += 1
            return AnyView(Text("pause"))
        }

        #expect(buildCount == 1)
    }
}

@Suite("GameShellUI — boardModalOverlayCoordinator environment key")
@MainActor
struct BoardModalOverlayCoordinatorEnvironmentTests {

    /// The default MUST be `nil`: that is what routes an iOS `fullScreenCover`
    /// board (presented outside the shell's TabView, so it never inherits the
    /// injected coordinator) back to in-place `.overlay` rendering.
    @Test("defaults to nil so unhosted boards render in place")
    func defaultsToNil() {
        #expect(EnvironmentValues().boardModalOverlayCoordinator == nil)
    }

    @Test("round-trips the injected coordinator")
    func roundTripsInjectedCoordinator() {
        let coordinator = BoardModalOverlayCoordinator()
        var environment = EnvironmentValues()

        environment.boardModalOverlayCoordinator = coordinator

        #expect(environment.boardModalOverlayCoordinator === coordinator)
    }
}

@Suite("GameShellUI — boardModalOverlay modifier")
@MainActor
struct BoardModalOverlayModifierTests {

    /// Compile-time sentinel: the modifier must stay applicable to ANY view with
    /// ANY overlay content, in both states. Both boards call it with their own
    /// `isModalOverlayActive` predicate, which is what makes the #763 "the
    /// preference must track the exact same condition as the overlay" invariant
    /// true by construction instead of by hand-maintained convention.
    @Test("applies to any view with any overlay content")
    func appliesToAnyView() {
        let active = Text("board").boardModalOverlay(isActive: true) {
            VStack { Text("paused") }
        }
        let inactive = Color.clear.boardModalOverlay(isActive: false) {
            Text("paused")
        }
        _ = active
        _ = inactive
    }
}
