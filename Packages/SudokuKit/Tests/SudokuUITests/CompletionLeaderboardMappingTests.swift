// CompletionLeaderboardMappingTests — issue #381.
//
// The Completion screen previously hard-coded the daily-easy leaderboard for
// every solve (RouteFactory built every `CompletionViewModel` with
// `LeaderboardIDs.id(for: .dailyEasy)`). These tests pin the puzzleId →
// leaderboard mapping: each daily difficulty posts to its own board, and
// practice solves submit to no leaderboard (nil id, no fetch, no crash).

import Foundation
import Testing
import GameCenterClient
import GameCenterTesting
import SudokuEngine
@testable import SudokuUI

@MainActor
@Suite("Completion — leaderboard id by puzzle difficulty (#381)")
struct CompletionLeaderboardMappingTests {

    // MARK: - puzzleId → leaderboard id mapping

    @Test func dailyEasyMapsToEasyLeaderboard() {
        let id = LiveRouteFactory.leaderboardId(forPuzzleId: "2026-05-19-easy")
        #expect(id == LeaderboardID.dailyEasy)
    }

    @Test func dailyMediumMapsToMediumLeaderboard() {
        let id = LiveRouteFactory.leaderboardId(forPuzzleId: "2026-05-19-medium")
        #expect(id == LeaderboardID.dailyMedium)
    }

    @Test func dailyHardMapsToHardLeaderboard() {
        let id = LiveRouteFactory.leaderboardId(forPuzzleId: "2026-05-19-hard")
        #expect(id == LeaderboardID.dailyHard)
    }

    @Test func practicePuzzleMapsToNoLeaderboard() {
        let id = LiveRouteFactory.leaderboardId(forPuzzleId: "practice-7Z9K-medium")
        #expect(id == nil)
    }

    // MARK: - nil leaderboard id is a safe no-op in the VM

    @Test func bootstrapWithNilLeaderboardDoesNotFetchOrCrash() async {
        let fake = FakeGameCenterClient()
        let viewModel = CompletionViewModel(
            puzzleId: "practice-7Z9K-medium",
            elapsedSeconds: 100,
            mistakeCount: 0,
            leaderboardId: nil,
            gameCenter: fake
        )
        await viewModel.bootstrap()
        // No leaderboard → no fetch operation recorded.
        let fetched = await fake.operations.contains { operation in
            if case .fetchLeaderboardSlice = operation { return true }
            return false
        }
        #expect(fetched == false)
    }

    // MARK: - nil leaderboard → .noLeaderboard, distinct from .unauthenticated (#383)

    // Practice solve: a nil leaderboard must land on `.noLeaderboard` (neutral
    // "not ranked" copy, no sign-in button), NOT `.unauthenticated`.
    @Test func bootstrapWithNilLeaderboardLandsOnNoLeaderboard() async {
        let fake = FakeGameCenterClient()
        let viewModel = CompletionViewModel(
            puzzleId: "practice-7Z9K-medium",
            elapsedSeconds: 100,
            mistakeCount: 0,
            leaderboardId: nil,
            gameCenter: fake
        )
        await viewModel.bootstrap()
        #expect(viewModel.state == .noLeaderboard)
    }

    // Daily solve with a real leaderboard but Game Center not authenticated:
    // the genuine auth-failure path must still resolve to `.unauthenticated`,
    // unchanged by the #383 reroute (which only touches the nil-id path).
    @Test func bootstrapWithRealLeaderboardButNotAuthenticatedStaysUnauthenticated() async {
        let fake = FakeGameCenterClient()
        await fake.setFetchLeaderboardSliceError(.notAuthenticated)
        let viewModel = CompletionViewModel(
            puzzleId: "2026-05-19-easy",
            elapsedSeconds: 100,
            mistakeCount: 0,
            leaderboardId: LeaderboardID.dailyEasy,
            gameCenter: fake
        )
        await viewModel.bootstrap()
        #expect(viewModel.state == .unauthenticated)
    }
}
