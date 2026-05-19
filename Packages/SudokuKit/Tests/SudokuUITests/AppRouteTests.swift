// AppRoute conformance + Codable round-trip.
//
// Pins the navigation surface so downstream Views can rely on:
// - `Hashable` (NavigationStack path identity)
// - `Sendable` (cross-actor passing from non-isolated callers)
// - `Codable` (state-restoration / deep-link payloads)

import Foundation
import Testing
@testable import SudokuUI

@Suite("AppRoute — conformance + codable")
struct AppRouteTests {

    @Test func allCasesHashableAndSendable() {
        // Compile-time: existential `any Hashable & Sendable` constructed.
        let routes: [AppRoute] = [
            .home,
            .daily,
            .practice,
            .board(puzzleId: "2026-05-19-easy"),
            .completion(puzzleId: "2026-05-19-easy", elapsedSeconds: 251),
            .leaderboard(leaderboardId: "com.wei18.sudoku.leaderboard.easy.daily.v1"),
            .settings
        ]
        let set = Set(routes)
        #expect(set.count == routes.count)
    }

    @Test func codableRoundTripCompletionToLeaderboard() throws {
        // Mirrors the CompletionView → LeaderboardView deep-link payload
        // described in design.md §How.5.2.
        let source: [AppRoute] = [
            .completion(puzzleId: "2026-05-19-medium", elapsedSeconds: 720),
            .leaderboard(leaderboardId: "com.wei18.sudoku.leaderboard.medium.daily.v1")
        ]
        let encoded = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode([AppRoute].self, from: encoded)
        #expect(decoded == source)
    }

    @Test func boardRouteHashIsStableAcrossEqualValues() {
        let lhs = AppRoute.board(puzzleId: "abc")
        let rhs = AppRoute.board(puzzleId: "abc")
        #expect(lhs.hashValue == rhs.hashValue)
        #expect(lhs == rhs)
    }
}
