// LeaderboardViewModel — scope toggle + friends-auth gating + slice cache.
//
// Per docs/designs/07-leaderboard.md + design.md §How.5.4. The scope toggle
// has 3 options (global all-time / today / friends); switching to `.friends`
// when status is `.notDetermined` triggers the system prompt before any
// fetch. `.denied` short-circuits with a CTA — no fetch is issued.

public import Foundation
public import GameCenterClient

public enum LeaderboardLoadState: Sendable, Equatable {
    case idle
    case loading
    case loaded(LeaderboardSlice)
    case unauthenticated
    case friendsDenied
    case failed(String)
}

@MainActor
@Observable
public final class LeaderboardViewModel {

    public let leaderboardId: String
    public private(set) var scope: LeaderboardScope = .globalAllTime
    public private(set) var state: LeaderboardLoadState = .idle

    private let gameCenter: any GameCenterClient
    private let limit: Int

    public init(
        leaderboardId: String,
        gameCenter: any GameCenterClient,
        limit: Int = 50
    ) {
        self.leaderboardId = leaderboardId
        self.gameCenter = gameCenter
        self.limit = limit
    }

    public func bootstrap() async {
        await fetch(scope: scope)
    }

    /// Switch scope. For `.friendsAllTime` this first checks (and possibly
    /// requests) friends authorization per §How.3 / step 7.5.
    public func setScope(_ next: LeaderboardScope) async {
        self.scope = next
        await fetch(scope: next)
    }

    private func fetch(scope: LeaderboardScope) async {
        if scope == .friendsAllTime {
            let status = await gameCenter.friendsAuthorizationStatus()
            switch status {
            case .denied, .restricted:
                state = .friendsDenied
                return
            case .notDetermined:
                let resolved = try? await gameCenter.requestFriendsAuthorization()
                guard resolved == .authorized else {
                    state = .friendsDenied
                    return
                }
            case .authorized:
                break
            }
        }
        state = .loading
        do {
            let slice = try await gameCenter.fetchLeaderboardSlice(
                leaderboardId: leaderboardId,
                scope: scope,
                around: nil,
                limit: limit
            )
            state = .loaded(slice)
        } catch GameCenterError.notAuthenticated {
            state = .unauthenticated
        } catch {
            state = .failed(String(describing: error))
        }
    }
}
