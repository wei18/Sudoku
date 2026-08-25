// BoardModalOverlayHoist — the #1019-adopted seam that lets a board's
// Pause / Completion overlay RENDER outside the shell's `TabView` while its
// STATE stays owned by the board.
//
// Why this exists (issue #1019's spike verdict, do not relitigate):
// `sidebarAdaptable` generates the sidebar / tab-bar chrome itself, so there is
// no user-authored sidebar `List` left to scope `.disabled()` to — it has to go
// on the whole `TabView`. Porting the old shape verbatim (overlay mounted
// `.overlay {}` deep inside the pushed route) then puts the overlay's OWN
// Resume / Close CTA inside the disabled subtree: the player is deadlocked in
// an undismissable modal (spike evidence 01–04). Rendering the overlay as a
// `ZStack` sibling OUTSIDE the disabled `TabView` restores #763's guarantee —
// sidebar and tab rows leave the a11y tree via `.isModal`, are physically
// un-tappable behind the overlay's own scrim, and the CTA stays live
// (evidence 06–10).
//
// The board keeps owning pause / terminal state; only PRESENTATION moves up.
// Down-flow dismissal rides the board's own state through the closures its
// overlay already captures (`onResume` / `dismiss()`), so no extra seam is
// needed for the buttons themselves.
//
// #763 invariant, now true BY CONSTRUCTION: the board used to hand-maintain an
// `isModalOverlayActive` predicate that "MUST track the EXACT same condition"
// as its `.overlay { … }`, with nothing enforcing it. `boardModalOverlay(
// isActive:content:)` takes that condition ONCE and drives both the rendering
// and `BoardModalOverlayActivePreferenceKey`, so the two cannot drift.

public import SwiftUI

// MARK: - HoistedOverlay

/// One overlay presentation registered with `BoardModalOverlayCoordinator`.
///
/// `id` is minted per presentation so the host can pin the rendered view's
/// SwiftUI identity with `.id(_:)`: the overlay keeps its own `@State` for the
/// whole time it is up, and a *new* presentation is a genuinely new view.
public struct HoistedOverlay: Identifiable {
    public let id: UUID
    public let view: AnyView

    public init(id: UUID = UUID(), view: AnyView) {
        self.id = id
        self.view = view
    }
}

// MARK: - BoardModalOverlayCoordinator

/// The up-flow seam a board uses to hand its full-screen-intent overlay to the
/// shell root for rendering. Owned by `RootShellView` as `@State` and injected
/// through `\.boardModalOverlayCoordinator`.
///
/// Only boards hosted INSIDE a tab's `NavigationStack` (macOS today, iPad
/// regular later) see a non-`nil` coordinator. On iOS a board is presented as a
/// `fullScreenCover` attached OUTSIDE the `TabView`, so it inherits the
/// environment default (`nil`) and `boardModalOverlay(isActive:content:)`
/// renders in place — the behavior iOS already got for free from the cover.
@MainActor
@Observable
public final class BoardModalOverlayCoordinator {

    /// The overlay currently hoisted, or `nil` when no board overlay is up.
    public private(set) var content: HoistedOverlay?

    public init() {}

    /// Register an overlay for hoisted rendering, replacing any current one.
    ///
    /// Called on the board's `false → true` transition only — see
    /// `boardModalOverlay(isActive:content:)` for why re-registering on every
    /// render would be wrong.
    public func present(_ makeView: () -> AnyView) {
        content = HoistedOverlay(view: makeView())
    }

    /// Clear the hoisted overlay. Safe to call when nothing is presented.
    public func dismiss() {
        content = nil
    }
}

// MARK: - Environment

private struct BoardModalOverlayCoordinatorKey: EnvironmentKey {
    // Computed (not a stored `static let`) because the value is a non-`Sendable`
    // `@MainActor` class: a stored global of that type would need `Sendable`,
    // while returning `nil` from a `nonisolated` getter is free of shared state.
    static var defaultValue: BoardModalOverlayCoordinator? { nil }
}

extension EnvironmentValues {
    /// The shell-root overlay coordinator, or `nil` when the current view is not
    /// hosted inside the shell's `TabView` (iOS `fullScreenCover` boards, plus
    /// every preview / test host that mounts a board standalone).
    public var boardModalOverlayCoordinator: BoardModalOverlayCoordinator? {
        get { self[BoardModalOverlayCoordinatorKey.self] }
        set { self[BoardModalOverlayCoordinatorKey.self] = newValue }
    }
}

// MARK: - View.boardModalOverlay

extension View {
    /// Mount a board's full-screen-intent overlay (Pause / Completion) and
    /// publish `BoardModalOverlayActivePreferenceKey` from the same condition.
    ///
    /// Two rendering modes, chosen by whether a `BoardModalOverlayCoordinator`
    /// is in the environment:
    ///
    /// - **No coordinator** (iOS `fullScreenCover` boards, previews, tests):
    ///   renders `.overlay { if isActive { content() } }` — the pre-#1020
    ///   in-place shape, which is correct there because the cover is presented
    ///   outside the `TabView` and already covers the whole screen.
    /// - **Coordinator present** (a board pushed inside a tab's
    ///   `NavigationStack`): registers the overlay with the coordinator so
    ///   `RootShellView` renders it as a `ZStack` sibling OUTSIDE the disabled
    ///   `TabView` (#1019's adopted shape).
    ///
    /// **Registration happens only on the `false → true` edge** (plus
    /// `.onAppear` when the view arrives already active). Re-registering on
    /// every render would mint a new `HoistedOverlay.id` each time and destroy
    /// the overlay's own SwiftUI identity — its local `@State` (animation
    /// phases, expanded sections) would reset mid-presentation.
    ///
    /// **Why the closure-captured board state still works from up there:**
    /// - `@Observable` values read inside the hoisted body (the board's view
    ///   model, the completion VM) register observation against the hoisted
    ///   view's OWN body evaluation, so they keep driving re-renders normally.
    /// - `@Binding` / `@State` accessed through closures the overlay captured
    ///   (`onResume`, `dismiss`) read and write the board's live storage — the
    ///   property wrapper holds a reference to it, not a copy.
    /// - The overlay's own local state lives in the hoisted view, whose identity
    ///   is pinned by `.id(hoisted.id)` at the host.
    ///
    /// The one thing that IS snapshotted is a value read *eagerly* while
    /// building `content()` (e.g. an `if let` on the board's `@State`). That is
    /// safe because `isActive` is by construction the disjunction of exactly the
    /// branches inside `content()`, so the branch taken at registration is the
    /// branch that made it active.
    ///
    /// - Parameters:
    ///   - isActive: the single condition driving BOTH the overlay's visibility
    ///     and the published preference. Passing the board's own
    ///     `isModalOverlayActive` predicate here is what makes #763's
    ///     "must track the exact same condition" invariant unbreakable.
    ///   - content: the overlay view. Not evaluated while `isActive` is `false`.
    public func boardModalOverlay(
        isActive: Bool,
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        modifier(BoardModalOverlayModifier(isActive: isActive, overlayContent: content))
    }
}

// MARK: - BoardModalOverlayModifier

private struct BoardModalOverlayModifier<OverlayContent: View>: ViewModifier {
    let isActive: Bool
    let overlayContent: () -> OverlayContent

    @Environment(\.boardModalOverlayCoordinator) private var coordinator

    func body(content: Content) -> some View {
        content
            .overlay {
                // In-place branch only. When a coordinator is present the
                // overlay must NOT also render here, or it would be drawn twice
                // (once inside the disabled TabView, once hoisted) and the
                // disabled copy would swallow the taps meant for the live one.
                if coordinator == nil, isActive {
                    overlayContent()
                }
            }
            // #763: published unconditionally, from the same `isActive` the
            // rendering above uses. `RootShellView` reads it to disable the
            // whole TabView while any board overlay is up.
            .preference(key: BoardModalOverlayActivePreferenceKey.self, value: isActive)
            .onAppear { if isActive { syncHoist(active: true) } }
            .onChange(of: isActive) { _, active in syncHoist(active: active) }
            // A board torn down (popped, or its tab unloaded) while its overlay
            // is up would otherwise strand the hoisted view on screen with no
            // board behind it to dismiss it.
            .onDisappear { coordinator?.dismiss() }
    }

    @MainActor
    private func syncHoist(active: Bool) {
        guard let coordinator else { return }
        if active {
            coordinator.present { AnyView(overlayContent()) }
        } else {
            coordinator.dismiss()
        }
    }
}
