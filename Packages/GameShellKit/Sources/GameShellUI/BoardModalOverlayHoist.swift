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
// presentation:content:)` takes that ONE value and drives both the in-place and
// the hoisted rendering, so the two cannot drift.
//
// #1020: the shell does NOT observe a preference to learn an overlay is up — it
// reads this coordinator. Observing `BoardModalOverlayActivePreferenceKey` from
// the shell root unmounted the pushed board on macOS; see `RootShellView`'s
// header. That key is gone.

public import SwiftUI
internal import Foundation

// MARK: - BoardModalPresentation

/// Which full-screen-intent overlay a board is showing.
///
/// Shared by both games (mirror principle): the branches are the same, only the
/// per-game copy inside them differs. Used as the `presentation` key of
/// `boardModalOverlay(presentation:content:)`, so switching between branches —
/// e.g. a solve landing while the pause menu is up — re-registers the hoisted
/// overlay instead of leaving the previous branch's snapshot on screen.
public enum BoardModalPresentation: Hashable, Sendable {
    /// Post-game Completion surface. Takes precedence over the others: once a
    /// session is terminal, that is what the player must see.
    case completion
    /// The pause menu over a live session.
    case pause
    /// The pre-first-move "leave?" confirmation, which is not a real pause —
    /// resuming just drops the prompt instead of restarting a stopped clock.
    case leaveConfirmation
}

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
/// environment default (`nil`) and `boardModalOverlay(presentation:content:)`
/// renders in place — the behavior iOS already got for free from the cover.
@MainActor
@Observable
public final class BoardModalOverlayCoordinator {

    /// The overlay currently hoisted, or `nil` when no board overlay is up.
    public private(set) var content: HoistedOverlay?

    public init() {}

    /// Register an overlay for hoisted rendering, replacing any current one, and
    /// return the identity minted for it.
    ///
    /// Called on a PRESENTATION CHANGE only (nil→key, or key→different key), not
    /// on every render — see `boardModalOverlay(presentation:content:)`.
    @discardableResult
    public func present(_ makeView: () -> AnyView) -> UUID {
        let overlay = HoistedOverlay(view: makeView())
        content = overlay
        return overlay.id
    }

    /// Clear the hoisted overlay. Safe to call when nothing is presented.
    public func dismiss() {
        content = nil
    }

    /// Clear the hoisted overlay only if `id` is the presentation currently up.
    ///
    /// A board that is torn down must not wipe an overlay some LATER
    /// presentation already installed — during a transition the outgoing and
    /// incoming boards briefly coexist, and an unscoped dismiss from the
    /// outgoing one would blank the incoming one's overlay.
    public func dismiss(id: UUID?) {
        guard let id, content?.id == id else { return }
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
    /// Mount a board's full-screen-intent overlay (Pause / Completion).
    ///
    /// Two rendering modes, chosen by whether a `BoardModalOverlayCoordinator`
    /// is in the environment:
    ///
    /// - **No coordinator** (iOS `fullScreenCover` boards, previews, tests):
    ///   renders in place via `.overlay { … }` — correct there, because the
    ///   cover is presented outside the shell's `TabView` and already covers the
    ///   whole screen.
    /// - **Coordinator present** (a board pushed inside a tab's
    ///   `NavigationStack`): hands the overlay to the coordinator so
    ///   `RootShellView` renders it as a ZStack sibling OUTSIDE the `TabView`
    ///   (#1019's adopted shape), where its own CTA stays live.
    ///
    /// ## Why a KEY and not a Bool
    ///
    /// The hoisted branch has to snapshot `content()` at registration time, so
    /// it must re-register whenever the overlay's IDENTITY changes — not merely
    /// when one goes up or comes down. A `Bool` cannot express that: completion
    /// replacing pause, or a leave-confirmation becoming a real pause, keeps the
    /// flag `true` the whole way through and would leave the FIRST branch's
    /// snapshot on screen. Passing a key makes every such switch observable, and
    /// each change mints a fresh `HoistedOverlay.id`.
    ///
    /// Equal keys mean "the same presentation", so a re-render with an unchanged
    /// key does NOT re-register — which is what keeps the overlay's own `@State`
    /// (animation phases, expanded sections) alive for as long as it is up.
    ///
    /// ## What the snapshot does and does not track
    ///
    /// Live, because they are read inside the hoisted view's OWN body or through
    /// a reference the closure captured:
    /// - `@Observable` values (the board's view model, the completion VM),
    /// - `@Binding` / `@State` reached through captured closures (`onResume`,
    ///   `dismiss`) — the wrapper points at the board's live storage.
    ///
    /// Frozen at registration: anything read EAGERLY while building `content()`,
    /// e.g. `if let completionViewModel` on the board's own `@State`. That is
    /// precisely what the key exists to handle — change the key whenever a
    /// different eager branch should be taken.
    ///
    /// - Parameters:
    ///   - key: identity of the presentation to show, or `nil` for "no overlay".
    ///   - content: the overlay view. Not evaluated while `key` is `nil`.
    public func boardModalOverlay<Key: Hashable>(
        presentation key: Key?,
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        modifier(BoardModalOverlayModifier(presentation: key, overlayContent: content))
    }
}

// MARK: - BoardModalOverlayModifier

private struct BoardModalOverlayModifier<Key: Hashable, OverlayContent: View>: ViewModifier {
    let presentation: Key?
    let overlayContent: () -> OverlayContent

    @Environment(\.boardModalOverlayCoordinator) private var coordinator
    /// Identity of the presentation THIS board installed, so teardown can clear
    /// only its own — see `BoardModalOverlayCoordinator.dismiss(id:)`.
    @State private var presentedID: UUID?

    func body(content: Content) -> some View {
        content
            .overlay {
                // In-place branch only. With a coordinator present the overlay
                // must NOT also render here, or it would be drawn twice — once
                // buried in the tab content and once hoisted — and the buried
                // copy would swallow taps meant for the live one.
                if coordinator == nil, presentation != nil {
                    overlayContent()
                }
            }
            .onAppear { syncHoist(to: presentation) }
            .onChange(of: presentation) { _, key in syncHoist(to: key) }
            // A board popped (or its tab unloaded) while its overlay is up would
            // otherwise strand that overlay on screen with no board behind it.
            .onDisappear {
                coordinator?.dismiss(id: presentedID)
                presentedID = nil
            }
    }

    @MainActor
    private func syncHoist(to key: Key?) {
        guard let coordinator else { return }
        guard key != nil else {
            coordinator.dismiss(id: presentedID)
            presentedID = nil
            return
        }
        presentedID = coordinator.present { AnyView(overlayContent()) }
    }
}
