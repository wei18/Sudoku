// FakeLeaderboardLoader — scripted `LeaderboardLoader` for tests.

import Foundation
public import GameCenterClient

public actor FakeLeaderboardLoader: LeaderboardLoader {
    public var scriptedSlice: LeaderboardSlice
    public private(set) var calls: [Call] = []

    public struct Call: Sendable, Equatable {
        public let leaderboardId: String
        public let scope: LeaderboardScope
        public let aroundLocalPlayer: Bool
        public let limit: Int
    }

    public init(scriptedSlice: LeaderboardSlice? = nil) {
        self.scriptedSlice = scriptedSlice ?? LeaderboardSlice(
            leaderboardId: "",
            scope: .globalAllTime,
            entries: [],
            totalPlayerCount: 0,
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
    }

    public func setScriptedSlice(_ slice: LeaderboardSlice) {
        self.scriptedSlice = slice
    }

    public func loadSlice(
        leaderboardId: String,
        scope: LeaderboardScope,
        aroundLocalPlayer: Bool,
        limit: Int
    ) async throws -> LeaderboardSlice {
        calls.append(Call(leaderboardId: leaderboardId, scope: scope, aroundLocalPlayer: aroundLocalPlayer, limit: limit))
        return scriptedSlice
    }
}
