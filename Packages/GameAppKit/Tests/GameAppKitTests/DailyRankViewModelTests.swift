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

    // MARK: - #983 follow-up: own-rank second fetch (aroundLocalPlayer: true)

    /// Local player isn't in the top-10 slice, so `load(tab:scope:key:)` fires
    /// a second, player-centred fetch. That response also happens to include
    /// a rival (`P9010`) already present in the top slice — pinning that the
    /// second fetch only ever contributes `localPlayerEntry`; it must never
    /// merge/duplicate into `topEntries`. If a future edit replaced the
    /// `own?.entries.first { ... }` filter with something that appended
    /// `own.entries` into `topEntries`, `topEntries.count` would grow past 10
    /// and this test would fail.
    @Test func ownRankResolvedViaSecondFetchDedupesAgainstTopSlice() async {
        let fake = FakeGameCenterClient()
        let topEntries = (1...10).map { rank in
            LeaderboardEntry(
                rank: rank,
                player: PlayerSummary(teamPlayerId: "P90\(String(format: "%02d", rank))", displayName: "Rival\(rank)"),
                score: 1000 - rank
            )
        }
        await fake.setLeaderboardSlice(LeaderboardSlice(
            leaderboardId: "com.wei18.sudoku.leaderboard.easy.daily.v1",
            scope: .globalAllTime,
            entries: topEntries,
            totalPlayerCount: 500,
            fetchedAt: Date(timeIntervalSince1970: 0)
        ))
        let ownEntry = LeaderboardEntry(rank: 47, player: localPlayer, score: 930)
        await fake.setOwnRankSlice(LeaderboardSlice(
            leaderboardId: "com.wei18.sudoku.leaderboard.easy.daily.v1",
            scope: .globalAllTime,
            // Includes P9010 (already in topEntries) ahead of the local
            // player's own entry — the dedupe case.
            entries: [topEntries[9], ownEntry],
            totalPlayerCount: 500,
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
        #expect(result.topEntries == topEntries, "top slice must be untouched by the second fetch")
        #expect(result.topEntries.count == 10)
        #expect(result.localPlayerEntry == ownEntry)
        #expect(result.localPlayerInTop == false)

        let calls = await fake.operations
        #expect(calls.contains(.fetchLeaderboardSlice(
            leaderboardId: "com.wei18.sudoku.leaderboard.easy.daily.v1",
            scope: .globalAllTime,
            aroundLocalPlayer: true,
            limit: 5
        )))
    }

    /// When the local player IS already inside the top slice, no second
    /// fetch should fire at all — pins the guard that gates the second call.
    @Test func localPlayerInTopSliceSkipsSecondFetch() async {
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

        let calls = await fake.operations
        #expect(!calls.contains(where: { operation in
            if case .fetchLeaderboardSlice(_, _, let aroundLocalPlayer, _) = operation { return aroundLocalPlayer }
            return false
        }))
    }

    /// The second, player-centred fetch fails (e.g. offline mid-load). The
    /// top slice already succeeded, so the screen must still render it —
    /// `.loaded` with `localPlayerEntry == nil` — rather than the `try?` in
    /// `load(tab:scope:key:)` being replaced by `try` and the whole screen
    /// falling through to `.failed(.network)`. Flipping that `try?` back to
    /// `try` is exactly what would turn this test red.
    @Test func secondFetchFailureDegradesToTopSliceOnlyRatherThanFailingScreen() async {
        let fake = FakeGameCenterClient()
        let topEntries = [
            LeaderboardEntry(rank: 1, player: PlayerSummary(teamPlayerId: "P9999", displayName: "Rival"), score: 90)
        ]
        await fake.setLeaderboardSlice(LeaderboardSlice(
            leaderboardId: "com.wei18.sudoku.leaderboard.easy.daily.v1",
            scope: .globalAllTime,
            entries: topEntries,
            totalPlayerCount: 500,
            fetchedAt: Date(timeIntervalSince1970: 0)
        ))
        await fake.setOwnRankError(.underlying(domain: "test", code: 2, description: "own-rank fetch offline"))

        let viewModel = DailyRankViewModel(
            gameCenter: fake,
            tabs: makeTabs(),
            initialAuthState: .authenticated(localPlayer)
        )
        await viewModel.onAppear()

        guard case .loaded(let result) = viewModel.state else {
            Issue.record("expected .loaded (degraded) even though the second fetch failed, got \(viewModel.state)")
            return
        }
        #expect(result.topEntries == topEntries)
        #expect(result.localPlayerEntry == nil)
    }

    // MARK: - #983 follow-up: stale-response drop on tab/scope switch

    /// The "easy" tab's fetch is gated so it stays in flight while the user
    /// switches to "medium" and back. `commit(_:for:)` must drop the stale
    /// "easy" response that finally lands while "medium" is showing, leaving
    /// `cache[easy]` at `.loading` — NOT the stale payload. Proof that the
    /// guard is load-bearing: if `commit(_:for:)` were changed to
    /// unconditionally write (`cache[key] = state`, guard deleted), the stale
    /// response would land in the cache as `.loaded` WHILE the user is on
    /// "medium"; switching back to "easy" would then hit
    /// `loadIfNeeded()`'s `if case .loaded = cache[key] { return }` early-out
    /// and immediately show the stale entry — skipping a fresh fetch
    /// entirely. This test reads `viewModel.state` synchronously right after
    /// `selectTab("easy")`, before the scheduler can run any newly-spawned
    /// refetch `Task`, so it can only observe what the stale response left
    /// behind.
    @Test func staleResponseDroppedAfterSwitchingAwayAndBack() async {
        let fake = GatedLeaderboardGameCenter(localPlayer: localPlayer)
        let staleEntries = [LeaderboardEntry(rank: 1, player: PlayerSummary(teamPlayerId: "STALE", displayName: "Stale"), score: 1)]
        let freshEntries = [LeaderboardEntry(rank: 1, player: PlayerSummary(teamPlayerId: "FRESH", displayName: "Fresh"), score: 2)]
        await fake.setSlice(LeaderboardSlice(
            leaderboardId: "com.wei18.sudoku.leaderboard.easy.daily.v1",
            scope: .globalAllTime, entries: staleEntries, totalPlayerCount: 1,
            fetchedAt: Date(timeIntervalSince1970: 0)
        ), for: "com.wei18.sudoku.leaderboard.easy.daily.v1")
        await fake.setSlice(LeaderboardSlice(
            leaderboardId: "com.wei18.sudoku.leaderboard.medium.daily.v1",
            scope: .globalAllTime, entries: freshEntries, totalPlayerCount: 1,
            fetchedAt: Date(timeIntervalSince1970: 0)
        ), for: "com.wei18.sudoku.leaderboard.medium.daily.v1")
        await fake.hold(leaderboardId: "com.wei18.sudoku.leaderboard.easy.daily.v1")

        let viewModel = DailyRankViewModel(
            gameCenter: fake,
            tabs: makeTabs(),
            initialAuthState: .authenticated(localPlayer)
        )

        // Kick off "easy"'s fetch (default selection); it suspends on the gate.
        let staleLoad = Task { await viewModel.onAppear() }
        await fake.waitUntilHeld()
        #expect(viewModel.state == .loading)

        // Switch away before "easy" resolves; "medium" fetches and commits
        // normally (its key differs, so nothing about this alone exercises
        // the guard — the guard is proven by the read after switching back).
        viewModel.selectTab("medium")
        var attempts = 0
        while viewModel.state != .loaded(DailyRankResult(topEntries: freshEntries, localPlayerEntry: nil, localPlayerId: "P0001")), attempts < 200 {
            await Task.yield()
            attempts += 1
        }
        #expect(viewModel.state == .loaded(DailyRankResult(topEntries: freshEntries, localPlayerEntry: nil, localPlayerId: "P0001")))

        // Release "easy"'s gated fetch — it resolves now, while "medium" is
        // still the current selection, and commit(_:for:) must drop it.
        await fake.release()
        await staleLoad.value

        // Switch back to "easy" and read state IMMEDIATELY — synchronous,
        // before the newly-spawned refetch Task can run — so this can only
        // reflect what the (dropped-or-not) stale response left in the cache.
        viewModel.selectTab("easy")
        #expect(viewModel.state == .loading, "a dropped stale response must leave \"easy\" pending a fresh fetch, not showing stale data")
    }
}
