// BoardModalOverlayHoistTests — pins the #1019/#1020 overlay-hoisting seam.
//
// Covered here: the coordinator's present/dismiss transitions, the
// identity-scoped dismiss that stops a torn-down board from wiping a newer
// presentation, the environment key's `nil` default (which is what routes iOS
// `fullScreenCover` boards back to in-place rendering), and the routing the
// modifier performs in each mode — asserted through a real `NSHostingView`, the
// same AppKit-hosted path `ScaledSpacingTests` uses.
//
// NOT covered here, deliberately: that a paused board leaves the shell's
// sidebar / tab rows un-tappable while its own CTA stays live. A bare hosting
// view mounts none of the real `sidebarAdaptable` machinery, so a unit test of
// that property passes for the wrong reason. It is verified natively by
// `SudokuE2ETests.test_pauseOverlayLocksShellOnMac_1019`.

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

    @Test("present registers the built view and returns its identity")
    func presentRegistersContent() {
        let coordinator = BoardModalOverlayCoordinator()

        let id = coordinator.present { AnyView(Text("pause")) }

        #expect(coordinator.content?.id == id)
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

    /// Each presentation mints a fresh id — `RootShellView` pins the rendered
    /// view's identity with `.id(hoisted.id)`, so a NEW presentation must be a
    /// new identity (fresh local `@State`).
    @Test("each presentation gets a distinct identity")
    func presentationsHaveDistinctIdentities() {
        let coordinator = BoardModalOverlayCoordinator()

        let first = coordinator.present { AnyView(Text("pause")) }
        let second = coordinator.present { AnyView(Text("completion")) }

        #expect(first != second)
        #expect(coordinator.content?.id == second)
    }

    /// The overlay body must not be built while nothing is presented — building
    /// it eagerly would read board state for an overlay that is not on screen.
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

    // MARK: - Identity-scoped dismissal

    /// A board being torn down must clear only ITS presentation. During a
    /// transition the outgoing and incoming boards briefly coexist, so an
    /// unscoped dismiss from the outgoing one would blank the incoming one's
    /// overlay.
    @Test("scoped dismiss ignores a stale identity")
    func scopedDismissIgnoresStaleIdentity() {
        let coordinator = BoardModalOverlayCoordinator()
        let stale = coordinator.present { AnyView(Text("outgoing")) }
        let current = coordinator.present { AnyView(Text("incoming")) }

        coordinator.dismiss(id: stale)

        #expect(coordinator.content?.id == current, "the newer presentation must survive")
    }

    @Test("scoped dismiss clears the presentation it owns")
    func scopedDismissClearsOwnIdentity() {
        let coordinator = BoardModalOverlayCoordinator()
        let id = coordinator.present { AnyView(Text("pause")) }

        coordinator.dismiss(id: id)

        #expect(coordinator.content == nil)
    }

    @Test("scoped dismiss with no identity is a no-op")
    func scopedDismissWithNilIsNoOp() {
        let coordinator = BoardModalOverlayCoordinator()
        coordinator.present { AnyView(Text("pause")) }

        coordinator.dismiss(id: nil)

        #expect(coordinator.content != nil)
    }
}

@Suite("GameShellUI — boardModalOverlayCoordinator environment key")
@MainActor
struct BoardModalOverlayCoordinatorEnvironmentTests {

    /// The default MUST be `nil`: that is what routes an iOS `fullScreenCover`
    /// board — presented outside the shell's TabView, so it never inherits the
    /// injected coordinator — back to in-place `.overlay` rendering.
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

#if canImport(AppKit)
import AppKit

/// Drives `BoardModalOverlayModifierRoutingTests.inPlaceBranchChangeReRegistersViaOnChange`:
/// an `@Observable` stand-in for a board's own presentation state, mutated in
/// place while a single hosting view stays mounted. Declared at file scope
/// (not nested in the test function) because the `@Observable` macro's
/// synthesized `Observable` conformance is an extension, and extensions
/// cannot attach to a type local to a function body.
@Observable
@MainActor
private final class BoardModalPresentationProbe {
    var presentation: BoardModalPresentation?
    init(presentation: BoardModalPresentation?) {
        self.presentation = presentation
    }
}

/// Hosts a board-shaped `boardModalOverlay` whose `presentation` key reads
/// from a `BoardModalPresentationProbe`, so mutating the probe changes the
/// key without remounting this view — the identity SwiftUI needs preserved
/// for `.onChange(of: presentation)` to be the seam that fires.
///
/// `onOverlayBuild` fires from INSIDE the `content` builder closure itself
/// (matching `BoardModalOverlayCoordinatorTests.contentBuilderIsNotRunEagerly`'s
/// approach), not via a `.onAppear` on the produced view: the coordinator only
/// captures the built `AnyView`, it never mounts it in a real hosting view, so
/// an `.onAppear` on that content would never fire here.
private struct BoardModalPresentationProbeHost: View {
    let probe: BoardModalPresentationProbe
    let coordinator: BoardModalOverlayCoordinator
    let onOverlayBuild: () -> Void

    var body: some View {
        Color.clear
            .boardModalOverlay(presentation: probe.presentation) {
                // The `let` below is load-bearing: a bare expression statement
                // is fed through `ViewBuilder.buildExpression`, and a Void
                // result fails to conform to `View`. Only a `let`/`var`
                // DECLARATION bypasses the builder transform — the same reason
                // SwiftUI's `let _ = print(...)` debug idiom exists.
                // swiftlint:disable:next redundant_discardable_let
                let _ = onOverlayBuild()
                Color.red
            }
            .environment(\.boardModalOverlayCoordinator, coordinator)
    }
}

@Suite("GameShellUI — boardModalOverlay routing")
@MainActor
struct BoardModalOverlayModifierRoutingTests {

    /// Renders a probe board through a real hosting view.
    private func host(
        presentation: BoardModalPresentation?,
        coordinator: BoardModalOverlayCoordinator?,
        onOverlayBuild: @escaping () -> Void = {}
    ) -> NSHostingView<some View> {
        var probe = AnyView(
            Color.clear.boardModalOverlay(presentation: presentation) {
                Color.red.onAppear(perform: onOverlayBuild)
            }
        )
        if let coordinator {
            probe = AnyView(probe.environment(\.boardModalOverlayCoordinator, coordinator))
        }
        let view = NSHostingView(rootView: probe)
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        view.layoutSubtreeIfNeeded()
        return view
    }

    /// With a coordinator in the environment the overlay is HANDED UP rather
    /// than drawn in place — that hand-off is the whole point of the hoist.
    @Test("hoisted mode registers the overlay with the coordinator")
    func hoistedModeRegisters() {
        let coordinator = BoardModalOverlayCoordinator()

        _ = host(presentation: .pause, coordinator: coordinator)

        #expect(coordinator.content != nil)
    }

    /// No coordinator (iOS cover, previews, snapshot hosts) → nothing to hand
    /// up, and the in-place `.overlay` branch does the rendering.
    @Test("in-place mode leaves the coordinator untouched")
    func inPlaceModeDoesNotRegister() {
        let coordinator = BoardModalOverlayCoordinator()

        _ = host(presentation: .pause, coordinator: nil)

        #expect(coordinator.content == nil)
    }

    @Test("a nil presentation registers nothing")
    func nilPresentationRegistersNothing() {
        let coordinator = BoardModalOverlayCoordinator()

        _ = host(presentation: nil, coordinator: coordinator)

        #expect(coordinator.content == nil)
    }

    /// The MAJOR review finding this API exists for: a branch-to-branch switch
    /// (pause → completion) keeps "an overlay is up" true throughout, so a Bool
    /// would never re-register and the FIRST branch's snapshot would stay on
    /// screen. A changed key must mint a new presentation.
    @Test("changing branch while active re-registers with a new identity")
    func branchChangeReRegisters() {
        let coordinator = BoardModalOverlayCoordinator()
        _ = host(presentation: .pause, coordinator: coordinator)
        let pauseID = coordinator.content?.id

        _ = host(presentation: .completion, coordinator: coordinator)

        #expect(pauseID != nil)
        #expect(coordinator.content?.id != pauseID, "completion must replace the pause snapshot")
    }

    /// `branchChangeReRegisters` above mounts TWO separate `NSHostingView`s —
    /// two cold starts — so it only ever exercises `.onAppear` → `syncHoist`.
    /// The production case this modifier exists for is a LIVE board whose
    /// `modalOverlayPresentation` flips `.pause` → `.completion` while its own
    /// view identity stays put; a real board never remounts to switch
    /// overlays. That path only reaches `.onChange(of: presentation)`, which
    /// no prior test drove. Here ONE hosting view stays up the whole time,
    /// and an `@Observable` probe's `presentation` is mutated in place to
    /// prove the `.onChange` branch re-registers on its own.
    @Test("an in-place branch change re-registers via onChange, not onAppear")
    func inPlaceBranchChangeReRegistersViaOnChange() {
        let coordinator = BoardModalOverlayCoordinator()
        var buildCount = 0
        let probe = BoardModalPresentationProbe(presentation: .pause)

        let view = NSHostingView(
            rootView: BoardModalPresentationProbeHost(probe: probe, coordinator: coordinator) {
                buildCount += 1
            }
        )
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        view.layoutSubtreeIfNeeded()

        let firstID = coordinator.content?.id
        #expect(firstID != nil)
        #expect(buildCount == 1)

        probe.presentation = .completion
        view.layoutSubtreeIfNeeded()

        #expect(coordinator.content != nil)
        #expect(
            coordinator.content?.id != firstID,
            "completion must mint a new identity even though the SAME view stayed mounted"
        )
        #expect(buildCount == 2, "the onChange branch must rebuild the overlay content exactly once more")

        probe.presentation = nil
        view.layoutSubtreeIfNeeded()

        #expect(coordinator.content == nil)
    }
}
#endif
