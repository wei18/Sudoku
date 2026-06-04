// MinesweeperCompletionViewModel — owns the post-game leaderboard slice +
// auth gating for the Minesweeper Completion surface (#292).
//
// Near-verbatim mirror of `SudokuUI.CompletionViewModel` (#49 / #150). Four
// observable states: `.loading` → `.loaded(slice)` / `.unauthenticated` /
// `.failed`. The embedded mini-slice is the post-game "炫耀面" affordance; the
// "View leaderboard" CTA presents Apple's native Game Center dashboard
// (`MinesweeperGameCenterDashboard`) instead of pushing a custom view.
//
// Deviation from Sudoku (#292 spec): the slice is centred on the LOCAL PLAYER
// (`aroundLocalPlayer: true`, the #150 path) rather than top-of-the-world, so a
// just-finished player sees their own neighbourhood of the ranking.

public import Foundation
public import GameCenterClient

public enum MinesweeperCompletionState: Sendable, Equatable {
    case loading
    case loaded(LeaderboardSlice)
    case unauthenticated
    case failed(String)
}

@MainActor
@Observable
public final class MinesweeperCompletionViewModel {

    /// `true` on a win, `false` on a loss. Drives the hero (You won / Boom) and
    /// whether the leaderboard slice is fetched at all (a loss has no score to
    /// compare, so we skip the fetch and stay on the hero-only surface).
    public let didWin: Bool
    public let elapsedSeconds: Int
    public let leaderboardId: String
    public private(set) var state: MinesweeperCompletionState = .loading

    private let gameCenter: (any GameCenterClient)?
    /// Idempotency latch for `.task` — once `bootstrap()` has resolved (or the
    /// testing seam ran) we don't re-enter the fetch on later lifecycle ticks.
    private var hasBootstrapped = false

    public init(
        didWin: Bool,
        elapsedSeconds: Int,
        leaderboardId: String,
        gameCenter: (any GameCenterClient)?
    ) {
        self.didWin = didWin
        self.elapsedSeconds = elapsedSeconds
        self.leaderboardId = leaderboardId
        self.gameCenter = gameCenter
    }

    /// Seed state for previews / snapshot tests that bypass the fetch.
    public func setStateForTesting(_ state: MinesweeperCompletionState) {
        self.state = state
        self.hasBootstrapped = true
    }

    /// User-triggered retry from the `.failed` block. Clears the latch so
    /// `bootstrap()` re-enters the fetch exactly once more.
    public func retry() async {
        hasBootstrapped = false
        await bootstrap()
    }

    public func bootstrap() async {
        // Skip if a prior call (or the testing seam) already settled state.
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        // A loss has no score to rank — show the hero-only surface (no slice).
        // `nil` client (MVP / preview) likewise can't fetch; treat as
        // unauthenticated so the CTA invites sign-in rather than spinning.
        guard didWin, let gameCenter else {
            state = .unauthenticated
            return
        }

        state = .loading
        do {
            // #292 / #150: centre the window on the local player.
            let slice = try await gameCenter.fetchLeaderboardSlice(
                leaderboardId: leaderboardId,
                scope: .globalAllTime,
                aroundLocalPlayer: true,
                limit: 5
            )
            state = .loaded(slice)
        } catch GameCenterError.notAuthenticated, GameCenterError.cancelled {
            state = .unauthenticated
        } catch {
            state = .failed(String(describing: error))
        }
    }

    /// CTA — present Apple's native Game Center dashboard focused on this
    /// difficulty's best-time leaderboard (mirrors Sudoku #49). Modal side
    /// effect: no route push, no path mutation.
    public func viewLeaderboardTapped() {
        MinesweeperGameCenterDashboard.present(leaderboardId: leaderboardId)
    }
}
