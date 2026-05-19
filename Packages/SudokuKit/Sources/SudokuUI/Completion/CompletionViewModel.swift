// CompletionViewModel — owns leaderboard slice + auth gating.
//
// Per docs/designs/06-completion.md + design.md §How.5.4. Four observable
// states: `.loading` → `.loaded(slice)` / `.unauthenticated` / `.failed`.
// Caller deep-links to LeaderboardView via the bound `path`.

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
    public var path: [AppRoute] = []

    private let gameCenter: any GameCenterClient

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
    }

    public func bootstrap() async {
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

    /// Deep-link CTA — pushes the full LeaderboardView onto the bound stack.
    public func viewLeaderboardTapped() {
        path.append(.leaderboard(leaderboardId: leaderboardId))
    }
}
