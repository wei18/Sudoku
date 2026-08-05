// DailyRankViewModelTests — the four #983 spec states + retry/sign-in/friends
// grant transitions, driven entirely through `FakeGameCenterClient` (never a
// live `authenticateHandler` — #766). No GameKit import here at all.

import Foundation
import Testing
import GameCenterClient
import GameCenterTesting
@testable import GameAppKit

@MainActor
private func makeTabs() -> [DailyRankTab] {
    [
        DailyRankTab(id: "easy", titleKey: "Easy", leaderboardId: "com.wei18.sudoku.leaderboard.easy.daily.v1"),
        DailyRankTab(id: "medium", titleKey: "Medium", leaderboardId: "com.wei18.sudoku.leaderboard.medium.daily.v1"),
    ]
}

private let localPlayer = PlayerSummary(teamPlayerId: "P0001", displayName: "TestPlayer")

@MainActor
@Suite("DailyRankViewModel — #983 states")
struct DailyRankViewModelTests {

    @Test func notSignedInFailureWhenUnauthenticated() async {
        let fake = FakeGameCenterClient()
        let viewModel = DailyRankViewModel(gameCenter: fake, tabs: makeTabs(), initialAuthState: .unauthenticated)
        await viewModel.onAppear()
        #expect(viewModel.state == .failed(.notSignedIn))
    }

    @Test func friendsNotAuthorizedFailureOnFriendsScope() async {
        let fake = FakeGameCenterClient()
        await fake.setFriendsStatus(.denied)
        let viewModel = DailyRankViewModel(
            gameCenter: fake,
            tabs: makeTabs(),
            initialAuthState: .authenticated(localPlayer)
        )
        viewModel.selectedScope = .friends
        await viewModel.onAppear()
        #expect(viewModel.state == .failed(.friendsNotAuthorized))
    }

    @Test func loadedPopulatesTopEntriesAndMarksLocalPlayerInTop() async {
        let fake = FakeGameCenterClient()
        let entries = [
            LeaderboardEntry(rank: 1, player: PlayerSummary(teamPlayerId: "P9999", displayName: "Rival"), score: 90),
            LeaderboardEntry(rank: 2, player: localPlayer, score: 120)
        ]
        await fake.setLeaderboardSlice(LeaderboardSlice(
            leaderboardId: "com.wei18.sudoku.leaderboard.easy.daily.v1",
            scope: .globalAllTime,
            entries: entries,
            totalPlayerCount: 2,
            fetchedAt: Date(timeIntervalSince1970: 0)
        ))
        let viewModel = DailyRankViewModel(
            gameCenter: fake,
            tabs: makeTabs(),
            initialAuthState: .authenticated(localPlayer)
        )
        await viewModel.onAppear()
        guard case .loaded(let result) = viewModel.state else {
            Issue.record("expected .loaded, got \(viewModel.state)")
            return
        }
        #expect(result.topEntries.count == 2)
        #expect(result.localPlayerInTop)
    }

    @Test func loadedEmptyWhenNoEntries() async {
        let fake = FakeGameCenterClient()
        // FakeGameCenterClient's default `leaderboardSlice` already has zero
        // entries — no scripting needed to hit the empty-state path.
        let viewModel = DailyRankViewModel(
            gameCenter: fake,
            tabs: makeTabs(),
            initialAuthState: .authenticated(localPlayer)
        )
        await viewModel.onAppear()
        guard case .loaded(let result) = viewModel.state else {
            Issue.record("expected .loaded, got \(viewModel.state)")
            return
        }
        #expect(result.topEntries.isEmpty)
        #expect(result.localPlayerEntry == nil)
    }

    @Test func retryRecoversFromNetworkFailure() async {
        let fake = FakeGameCenterClient()
        await fake.setFetchLeaderboardSliceError(.underlying(domain: "test", code: 1, description: "offline"))
        let viewModel = DailyRankViewModel(
            gameCenter: fake,
            tabs: makeTabs(),
            initialAuthState: .authenticated(localPlayer)
        )
        await viewModel.onAppear()
        #expect(viewModel.state == .failed(.network))

        await fake.setFetchLeaderboardSliceError(nil)
        await viewModel.retry()
        guard case .loaded = viewModel.state else {
            Issue.record("expected .loaded after retry, got \(viewModel.state)")
            return
        }
    }

    @Test func signInTransitionsNotSignedInToLoaded() async {
        let fake = FakeGameCenterClient()
        // Default `authResult` is `.authenticated(PlayerSummary(teamPlayerId: "P0001", ...))`.
        let viewModel = DailyRankViewModel(gameCenter: fake, tabs: makeTabs(), initialAuthState: .unauthenticated)
        await viewModel.onAppear()
        #expect(viewModel.state == .failed(.notSignedIn))

        await viewModel.signIn()
        guard case .loaded = viewModel.state else {
            Issue.record("expected .loaded after signIn, got \(viewModel.state)")
            return
        }
    }

    @Test func requestFriendsAccessGrantsAndReloadsFriendsScope() async {
        let fake = FakeGameCenterClient()
        await fake.setFriendsStatus(.denied)
        await fake.setRequestFriendsResult(.success(.authorized))
        let viewModel = DailyRankViewModel(
            gameCenter: fake,
            tabs: makeTabs(),
            initialAuthState: .authenticated(localPlayer)
        )
        viewModel.selectedScope = .friends
        await viewModel.onAppear()
        #expect(viewModel.state == .failed(.friendsNotAuthorized))

        await viewModel.requestFriendsAccess()
        guard case .loaded = viewModel.state else {
            Issue.record("expected .loaded after requestFriendsAccess, got \(viewModel.state)")
            return
        }
    }

    @Test func selectTabAndSelectScopeUpdateSelection() {
        let fake = FakeGameCenterClient()
        let viewModel = DailyRankViewModel(
            gameCenter: fake,
            tabs: makeTabs(),
            initialAuthState: .authenticated(localPlayer)
        )
        #expect(viewModel.selectedTabId == "easy")
        viewModel.selectTab("medium")
        #expect(viewModel.selectedTabId == "medium")
        #expect(viewModel.selectedTab.leaderboardId == "com.wei18.sudoku.leaderboard.medium.daily.v1")

        #expect(viewModel.selectedScope == .world)
        viewModel.selectScope(.friends)
        #expect(viewModel.selectedScope == .friends)
    }
}
