// UITestSignedOutGameCenterClientTests — #935 batch 4 N14 fake contract.
//
// The whole fake is `#if DEBUG` (defined in UITestFakeSeams.swift), so this
// suite is too. Confirms the one behavior the N14 E2E flow actually depends
// on — `authenticate()` returning `.unauthenticated` — plus the inert members
// stay harmless (never thrown, never crash) in case a future call site starts
// invoking them before the signed-out guard short-circuits.

#if DEBUG

import Testing
import GameCenterClient
import SudokuEngine
@testable import GameAppKit

@Suite("UITestSignedOutGameCenterClient (#935 batch 4)")
struct UITestSignedOutGameCenterClientTests {

    @Test func authenticateReturnsUnauthenticated() async throws {
        let fake = UITestSignedOutGameCenterClient()
        let state = try await fake.authenticate()
        #expect(state == .unauthenticated)
    }

    @Test func authStateUpdatesFinishesImmediately() async {
        let fake = UITestSignedOutGameCenterClient()
        var sawValue = false
        for await _ in await fake.authStateUpdates() {
            sawValue = true
        }
        #expect(sawValue == false)
    }

    @Test func friendsAuthorizationStatusIsNotDetermined() async {
        let fake = UITestSignedOutGameCenterClient()
        let status = await fake.friendsAuthorizationStatus()
        #expect(status == .notDetermined)
    }

    @Test func fetchLeaderboardSliceReturnsEmptySlice() async throws {
        let fake = UITestSignedOutGameCenterClient()
        let slice = try await fake.fetchLeaderboardSlice(
            leaderboardId: "any.leaderboard",
            scope: .globalAllTime,
            aroundLocalPlayer: false,
            limit: 10
        )
        #expect(slice.entries.isEmpty)
        #expect(slice.leaderboardId == "any.leaderboard")
    }
}

#endif
