import Foundation
import Testing
@testable import GameCenterClient
import GameCenterTesting

@Suite("GameCenterClient — leaderboard slice fetch")
struct LeaderboardSliceTests {

    private func makeSlice(entries: [LeaderboardEntry], total: Int = 0) -> LeaderboardSlice {
        LeaderboardSlice(
            leaderboardId: "lb",
            scope: .globalAllTime,
            entries: entries,
            totalPlayerCount: total,
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func globalTopForwardsToLoader() async throws {
        let entries = (1...10).map {
            LeaderboardEntry(
                rank: $0,
                player: PlayerSummary(teamPlayerId: "P\($0)", displayName: "P\($0)"),
                score: $0 * 100
            )
        }
        let loader = FakeLeaderboardLoader(scriptedSlice: makeSlice(entries: entries))
        let slice = try await LeaderboardSliceService.fetch(
            loader: loader,
            friendsStatus: { .notDetermined },
            requestFriendsAuthorization: { .notDetermined },
            leaderboardId: "lb",
            scope: .globalAllTime,
            around: nil,
            limit: 10
        )
        #expect(slice.entries.count == 10)
        let calls = await loader.calls
        #expect(calls.count == 1)
        #expect(calls[0].limit == 10)
        #expect(calls[0].scope == .globalAllTime)
    }

    @Test func aroundPlayerPassesPlayerThrough() async throws {
        let loader = FakeLeaderboardLoader()
        _ = try await LeaderboardSliceService.fetch(
            loader: loader,
            friendsStatus: { .authorized },
            requestFriendsAuthorization: { .authorized },
            leaderboardId: "lb",
            scope: .globalToday,
            around: "P50",
            limit: 10
        )
        let calls = await loader.calls
        #expect(calls[0].around == "P50")
    }

    @Test func friendsDeniedThrowsAccessError() async throws {
        let loader = FakeLeaderboardLoader()
        await #expect(throws: GameCenterError.friendsAccessDenied) {
            _ = try await LeaderboardSliceService.fetch(
                loader: loader,
                friendsStatus: { .denied },
                requestFriendsAuthorization: { .denied },
                leaderboardId: "lb",
                scope: .friendsAllTime,
                around: nil,
                limit: 10
            )
        }
        let calls = await loader.calls
        #expect(calls.isEmpty, "loader must not be invoked when friends access is denied")
    }

    @Test func friendsRestrictedThrowsAccessError() async throws {
        let loader = FakeLeaderboardLoader()
        await #expect(throws: GameCenterError.friendsAccessDenied) {
            _ = try await LeaderboardSliceService.fetch(
                loader: loader,
                friendsStatus: { .restricted },
                requestFriendsAuthorization: { .restricted },
                leaderboardId: "lb",
                scope: .friendsAllTime,
                around: nil,
                limit: 10
            )
        }
    }

    @Test func notDeterminedTriggersRequestThenProceeds() async throws {
        let loader = FakeLeaderboardLoader()
        let requestCount = RequestCounter()
        _ = try await LeaderboardSliceService.fetch(
            loader: loader,
            friendsStatus: { .notDetermined },
            requestFriendsAuthorization: {
                await requestCount.bump()
                return .authorized
            },
            leaderboardId: "lb",
            scope: .friendsAllTime,
            around: nil,
            limit: 10
        )
        #expect(await requestCount.count == 1)
        let calls = await loader.calls
        #expect(calls.count == 1, "loader runs after authorization is granted")
    }

    @Test func globalScopesDoNotTriggerFriendsRequest() async throws {
        let loader = FakeLeaderboardLoader()
        let requestCount = RequestCounter()
        _ = try await LeaderboardSliceService.fetch(
            loader: loader,
            friendsStatus: { .notDetermined },
            requestFriendsAuthorization: {
                await requestCount.bump()
                return .authorized
            },
            leaderboardId: "lb",
            scope: .globalAllTime,
            around: nil,
            limit: 10
        )
        #expect(await requestCount.count == 0)
    }
}

private actor RequestCounter {
    private(set) var count = 0
    func bump() { count += 1 }
}
