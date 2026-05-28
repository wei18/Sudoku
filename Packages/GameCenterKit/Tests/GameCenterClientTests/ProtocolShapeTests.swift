import Foundation
import Testing
@testable import GameCenterClient
import GameCenterTesting

@Suite("GameCenterClient — protocol shape")
struct GameCenterClientProtocolShapeTests {

    /// Compile-time check: every `GameCenterClient` is `Sendable`. If a
    /// future edit drops the `Sendable` requirement this generic constraint
    /// fails to compile and the test stops building.
    @Test func protocolIsSendable() {
        func requiresSendable<T: Sendable>(_: T.Type) {}
        requiresSendable((any GameCenterClient).self)
    }

    @Test func valueTypesAreSendableAndEquatable() {
        func requireSendableEquatable<T: Sendable & Equatable>(_: T.Type) {}
        requireSendableEquatable(GameCenterAuthState.self)
        requireSendableEquatable(PlayerSummary.self)
        requireSendableEquatable(LeaderboardKind.self)
        requireSendableEquatable(LeaderboardScope.self)
        requireSendableEquatable(LeaderboardEntry.self)
        requireSendableEquatable(LeaderboardSlice.self)
        requireSendableEquatable(AchievementProgress.self)
        requireSendableEquatable(FriendsAuthStatus.self)
        requireSendableEquatable(GameCenterError.self)
    }

    @Test func leaderboardKindRoundTripsRawValue() throws {
        for kind in LeaderboardKind.allCases {
            #expect(LeaderboardKind(rawValue: kind.rawValue) == kind)
        }
    }

    @Test func leaderboardScopeRoundTripsRawValue() throws {
        for scope in LeaderboardScope.allCases {
            #expect(LeaderboardScope(rawValue: scope.rawValue) == scope)
        }
    }

    @Test func authStateAuthenticatedHoldsPlayer() {
        let player = PlayerSummary(teamPlayerId: "abc", displayName: "Wei")
        let state = GameCenterAuthState.authenticated(player)
        switch state {
        case .authenticated(let observed): #expect(observed == player)
        default: Issue.record("expected .authenticated case")
        }
    }

    @Test func fakeClientConformsToProtocol() async throws {
        let client: any GameCenterClient = FakeGameCenterClient()
        let state = try await client.authenticate()
        switch state {
        case .authenticated: ()
        default: Issue.record("default scripted state should be authenticated")
        }
    }
}
