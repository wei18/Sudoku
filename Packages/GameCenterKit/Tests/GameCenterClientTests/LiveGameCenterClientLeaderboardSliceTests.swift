// LiveGameCenterClientLeaderboardSliceTests — issue #64: integration of
// `LeaderboardSliceService` into `LiveGameCenterClient.fetchLeaderboardSlice`.
//
// Previously `fetchLeaderboardSlice` was a `throw .notAuthenticated` stub
// (CompletionView's mini-slice always failed on device). The wiring now
// delegates to `LeaderboardSliceService.fetch(loader:...)` with `self`'s
// `friendsAuthorizationStatus()` / `requestFriendsAuthorization()` as the
// gating closures. These tests drive the wiring via `FakeLeaderboardLoader`
// + `FakeAuthDriver`.

import Foundation
import Testing
@testable import GameCenterClient
import GameCenterTesting

@Suite("LiveGameCenterClient — leaderboard slice wiring (issue #64)")
struct LiveGameCenterClientLeaderboardSliceTests {

    private func slice(scope: LeaderboardScope = .globalAllTime) -> LeaderboardSlice {
        LeaderboardSlice(
            leaderboardId: "lb",
            scope: scope,
            entries: [
                LeaderboardEntry(
                    rank: 1,
                    player: PlayerSummary(teamPlayerId: "P1", displayName: "P1"),
                    score: 100
                )
            ],
            totalPlayerCount: 1,
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeClient(loader: any LeaderboardLoader) -> LiveGameCenterClient {
        let driver = FakeAuthDriver(nextOutcome: .signedOut)
        return LiveGameCenterClient(
            authDriver: driver,
            submitScoreHook: { _, _ in },
            leaderboardLoader: loader
        )
    }

    @Test func globalAllTimeForwardsToLoader() async throws {
        let loader = FakeLeaderboardLoader(scriptedSlice: slice())
        let client = makeClient(loader: loader)

        let result = try await client.fetchLeaderboardSlice(
            leaderboardId: "lb",
            scope: .globalAllTime,
            around: nil,
            limit: 5
        )

        #expect(result.entries.count == 1)
        let calls = await loader.calls
        #expect(calls.count == 1)
        #expect(calls[0].leaderboardId == "lb")
        #expect(calls[0].scope == .globalAllTime)
        #expect(calls[0].limit == 5)
    }

    @Test func friendsScopeIsGatedAndThrowsWhenAuthDenied() async throws {
        let loader = FakeLeaderboardLoader(scriptedSlice: slice(scope: .friendsAllTime))
        // Default `LiveGameCenterClient.friendsAuthorizationStatus` returns
        // `.notDetermined` and `requestFriendsAuthorization` throws
        // `.friendsAccessDenied` — so the gate must throw and the loader
        // must never be invoked.
        let client = makeClient(loader: loader)

        await #expect(throws: GameCenterError.friendsAccessDenied) {
            _ = try await client.fetchLeaderboardSlice(
                leaderboardId: "lb",
                scope: .friendsAllTime,
                around: nil,
                limit: 5
            )
        }
        let calls = await loader.calls
        #expect(calls.isEmpty, "loader must not be invoked when friends auth is denied")
    }

    @Test func globalScopeBypassesFriendsRequest() async throws {
        let loader = FakeLeaderboardLoader(scriptedSlice: slice(scope: .globalToday))
        let client = makeClient(loader: loader)

        // `.globalToday` must not consult friends auth at all — the stub
        // `requestFriendsAuthorization` throwing would fail the test if it
        // were invoked.
        let result = try await client.fetchLeaderboardSlice(
            leaderboardId: "lb",
            scope: .globalToday,
            around: "P50",
            limit: 3
        )
        #expect(result.scope == .globalToday)
        let calls = await loader.calls
        #expect(calls.count == 1)
        #expect(calls[0].around == "P50")
        #expect(calls[0].scope == .globalToday)
    }
}
