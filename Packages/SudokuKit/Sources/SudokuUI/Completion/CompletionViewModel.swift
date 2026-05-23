// CompletionViewModel — owns leaderboard slice + auth gating.
//
// Per docs/designs/06-completion.md + docs/v1/design.md §How.5.4. Four observable
// states: `.loading` → `.loaded(slice)` / `.unauthenticated` / `.failed`.
// The embedded top-3 mini-slice stays (post-solve UX affordance); the
// "View full leaderboard" CTA presents Apple's native Game Center dashboard
// (issue #49, 2026-05-20) instead of pushing a custom view onto the stack.

public import Foundation
public import GameCenterClient

public enum CompletionState: Sendable, Equatable {
    case loading
    case loaded(LeaderboardSlice)
    case unauthenticated
    case failed(String)
}

@MainActor
@Observable
public final class CompletionViewModel {

    public let puzzleId: String
    public let elapsedSeconds: Int
    public let leaderboardId: String
    public private(set) var state: CompletionState = .loading

    private let gameCenter: any GameCenterClient
    /// Idempotency latch for `.task` — once `bootstrap()` has resolved (or
    /// the state was set via the testing seam) we don't re-enter the fetch
    /// path on subsequent SwiftUI lifecycle ticks.
    private var hasBootstrapped = false

    public init(
        puzzleId: String,
        elapsedSeconds: Int,
        leaderboardId: String,
        gameCenter: any GameCenterClient
    ) {
        self.puzzleId = puzzleId
        self.elapsedSeconds = elapsedSeconds
        self.leaderboardId = leaderboardId
        self.gameCenter = gameCenter
    }

    /// Initial state seed for previews / snapshot tests that bypass the
    /// fetch. Use one of the static factories instead of `bootstrap()`.
    public func setStateForTesting(_ state: CompletionState) {
        self.state = state
        self.hasBootstrapped = true
    }

    /// User-triggered retry from the `.failed` block. Clears the idempotency
    /// latch so `bootstrap()` will re-enter the fetch path exactly once more.
    public func retry() async {
        hasBootstrapped = false
        await bootstrap()
    }

    public func bootstrap() async {
        // Skip if a prior call (or the testing seam) already settled state.
        // Without this guard the `.task` re-entry from CompletionView would
        // overwrite `.loaded` / `.unauthenticated` / `.failed` back to
        // `.loading` on every view-lifecycle tick.
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        state = .loading
        do {
            let slice = try await gameCenter.fetchLeaderboardSlice(
                leaderboardId: leaderboardId,
                scope: .globalAllTime,
                around: nil,
                limit: 3
            )
            state = .loaded(slice)
        } catch GameCenterError.notAuthenticated, GameCenterError.cancelled {
            state = .unauthenticated
        } catch {
            state = .failed(String(describing: error))
        }
    }

    /// CTA — presents Apple's native Game Center dashboard focused on the
    /// just-solved difficulty's leaderboard (issue #49, 2026-05-20). Side
    /// effect: no stack push, no `path` mutation.
    public func viewLeaderboardTapped() {
        GameCenterDashboard.present(leaderboardId: leaderboardId)
    }
}
