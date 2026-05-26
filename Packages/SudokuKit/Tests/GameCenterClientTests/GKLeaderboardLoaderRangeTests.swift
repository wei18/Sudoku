// GKLeaderboardLoaderRangeTests — issue #140: verify the pure range
// arithmetic used by `GKLeaderboardLoader.loadSlice` to centre the
// fetched window on the local player's rank.
//
// The live `GKLeaderboard` calls themselves are exercised by Phase 10
// manual device validation (consistent with the COMPILE-ONLY stance of
// `GKLeaderboardLoader.swift`); these tests only cover the new
// `makeRange(centeredOnRank:limit:)` helper.

import Foundation
import Testing
@testable import GameCenterClient

@Suite("GKLeaderboardLoader — makeRange (issue #140)")
struct GKLeaderboardLoaderRangeTests {

    @Test func centresWindowOnRank() {
        let range = GKLeaderboardLoader.makeRange(centeredOnRank: 50, limit: 8)
        #expect(range.location == 46)
        #expect(range.length == 8)
    }

    @Test func clampsToOneWhenRankNearTop() {
        let range = GKLeaderboardLoader.makeRange(centeredOnRank: 2, limit: 8)
        #expect(range.location == 1)
        #expect(range.length == 8)
    }

    @Test func fallbackToTopNWhenNoRank() {
        let range = GKLeaderboardLoader.makeRange(centeredOnRank: nil, limit: 8)
        #expect(range.location == 1)
        #expect(range.length == 8)
    }
}
