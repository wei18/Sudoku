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

    public init(
        rootViewModel: GameRootViewModel<Route>,
        homeModes: [HomeMode: HomeModeContent<Route>],
        presentLeaderboard: (@MainActor () -> Void)? = nil
    ) {
        self.rootViewModel = rootViewModel
        self.homeModes = homeModes
        self.presentLeaderboard = presentLeaderboard
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

    public func select(_ mode: HomeMode) {
        // `.leaderboard` presents Apple's native GC dashboard (a side-effect,
        // not a stack push — issue #49). #513: guard on auth state; surface an
        // alert when GC is signed out.
        let content = homeModes[mode]
        if let route = content?.route {
            rootViewModel.path.append(route)
            return
        }
        // No route → leaderboard side-effect path.
        if case .authenticated = authState {
            // A game with a no-route (leaderboard) mode MUST inject
            // `presentLeaderboard`; otherwise the card is silently inert.
            // Assert in debug/test so a future game migration (MS / 2048)
            // can't ship an inert leaderboard card unnoticed (CR #566).
            assert(presentLeaderboard != nil, "leaderboard mode has no presentLeaderboard wired")
            presentLeaderboard?()
        } else {
            rootViewModel.showGameCenterSignedOutAlert = true
        }
    }
}
