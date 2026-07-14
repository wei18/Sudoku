// GameHomeViewModel — shared 4-mode home navigation VM (#557 SDD-005 C).
//
// Generalized from `SudokuUI.HomeViewModel`, whose logic was identical across
// all three games. Per-game bits are injected at construction:
//   - `homeModes` map: subtitle copy + route per `HomeMode`.
//   - `presentLeaderboard`: game-specific GC dashboard presenter (per-game
//     `GameCenterDashboard.present()` lives in each game's UI layer).
//   - The `GameRootViewModel` reference: path + authState + alert binding.
//
// #513: `authState` is read from the stable `GameRootViewModel` (injected) so
// the leaderboard card can gate on it without the VM owning a GC client.
// The signed-out alert flag lives on `GameRootViewModel.showGameCenterSignedOutAlert`
// (long-lived), NOT on this VM (computed-property footgun from
// swiftui-interaction-footguns — alert on transient VM never fires).

public import SwiftUI
public import GameShellUI
public import GameCenterClient

@MainActor
@Observable
public final class GameHomeViewModel<Route: Hashable & Sendable> {

    /// Stable reference to the root VM. Path + authState + alert flag are
    /// read/written through it so bindings survive re-renders.
    private let rootViewModel: GameRootViewModel<Route>

    /// Per-mode content: subtitle key + route (nil = leaderboard side-effect).
    private let homeModes: [HomeMode: HomeModeContent<Route>]

    /// Per-game Game Center leaderboard presenter. Each game has its own
    /// `GameCenterDashboard.present()` variant; injected here so GameAppKit
    /// never imports a per-game module.
    @ObservationIgnored private let presentLeaderboard: (@MainActor () -> Void)?

    /// #773: navigation target for the Home secondary-weight "Statistics"
    /// entry. `nil` → the entry is not rendered.
    @ObservationIgnored private let statsRoute: Route?

    public init(
        rootViewModel: GameRootViewModel<Route>,
        homeModes: [HomeMode: HomeModeContent<Route>],
        presentLeaderboard: (@MainActor () -> Void)? = nil,
        statsRoute: Route? = nil
    ) {
        self.rootViewModel = rootViewModel
        self.homeModes = homeModes
        self.presentLeaderboard = presentLeaderboard
        self.statsRoute = statsRoute
    }

    // MARK: - Navigation

    /// Current navigation path, forwarded to/from the root VM.
    public var path: [Route] {
        get { rootViewModel.path }
        set { rootViewModel.path = newValue }
    }

    /// Current Game Center auth state, read from the stable root VM.
    public var authState: GameCenterAuthState {
        rootViewModel.authState
    }

    // MARK: - Mode items

    /// The 4 shared modes bound to per-game subtitles + tap actions.
    /// Single source of truth for both the Home card grid and the sidebar.
    public var modeItems: [HomeModeItem] {
        HomeMode.allCases.map { mode in
            let content = homeModes[mode]
            return HomeModeItem(
                mode: mode,
                subtitleKey: content?.subtitleKey ?? "",
                onTap: { [weak self] in self?.select(mode) }
            )
        }
    }

    // MARK: - Statistics secondary entry (#773)

    /// Whether `HomeScreen`'s secondary-link slot should render the
    /// Statistics row — mirrors the `homeModes` pattern of "content presence
    /// implies UI presence" rather than a separate visibility flag.
    public var showsStatsEntry: Bool { statsRoute != nil }

    /// Pushes the configured Statistics route. No-op if `statsRoute` is `nil`
    /// (the entry would not be shown, so this should be unreachable from the
    /// UI, but stays a safe no-op for direct VM callers/tests).
    public func selectStats() {
        guard let statsRoute else { return }
        rootViewModel.path.append(statsRoute)
    }

    public func select(_ mode: HomeMode) {
        // `.leaderboard` presents Apple's native GC dashboard (a side-effect,
        // not a stack push — issue #49). #513: guard on auth state; surface an
        // alert when GC is signed out. #685: the guard itself now lives on
        // `GameRootViewModel.presentGameCenterOrAlert` so the Settings Game
        // Center row can share the exact same auth-gate.
        let content = homeModes[mode]
        if let route = content?.route {
            rootViewModel.path.append(route)
            return
        }
        // No route → leaderboard side-effect path.
        rootViewModel.presentGameCenterOrAlert {
            // A game with a no-route (leaderboard) mode MUST inject
            // `presentLeaderboard`; otherwise the card is silently inert.
            // Assert in debug/test so a future game migration (MS / 2048)
            // can't ship an inert leaderboard card unnoticed (CR #566).
            assert(presentLeaderboard != nil, "leaderboard mode has no presentLeaderboard wired")
            presentLeaderboard?()
        }
    }
}
