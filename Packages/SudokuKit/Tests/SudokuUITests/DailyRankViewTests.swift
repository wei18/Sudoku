// DailyRankViewTests — snapshot coverage for the shared #983 Daily Rank
// screen, Sudoku-parameterized (Easy/Medium/Hard tabs, Sudoku leaderboard
// ids). Mirrors HomeViewTests.swift's harness (FakeGameCenterClient,
// hostingView, assertViewStructure) — never a live `authenticateHandler`
// (#766).

#if canImport(AppKit)
import AppKit
import Foundation
import GameAppKit
import GameCenterClient
import GameCenterTesting
import SnapshotTesting
import SwiftUI
import Testing
@testable import SudokuUI

private let localPlayer = PlayerSummary(teamPlayerId: "P0001", displayName: "TestPlayer")

@MainActor
private func sudokuTabs() -> [DailyRankTab] {
    [
        DailyRankTab(id: "easy", titleKey: "Easy", leaderboardId: "com.wei18.sudoku.leaderboard.easy.daily.v1"),
        DailyRankTab(id: "medium", titleKey: "Medium", leaderboardId: "com.wei18.sudoku.leaderboard.medium.daily.v1"),
        DailyRankTab(id: "hard", titleKey: "Hard", leaderboardId: "com.wei18.sudoku.leaderboard.hard.daily.v1")
    ]
}

/// Populated: 3 entries, local player at rank 2 (inside the top slice, so
/// no separate "Your Rank" section — the common/likely-frequency case).
@MainActor
private func makePopulatedViewModel() async -> DailyRankViewModel {
    let fake = FakeGameCenterClient()
    await fake.setLeaderboardSlice(LeaderboardSlice(
        leaderboardId: "com.wei18.sudoku.leaderboard.easy.daily.v1",
        scope: .globalAllTime,
        entries: [
            LeaderboardEntry(rank: 1, player: PlayerSummary(teamPlayerId: "P0777", displayName: "Aiko"), score: 87),
            LeaderboardEntry(rank: 2, player: localPlayer, score: 102),
            LeaderboardEntry(rank: 3, player: PlayerSummary(teamPlayerId: "P0333", displayName: "Marco"), score: 115)
        ],
        totalPlayerCount: 3,
        fetchedAt: Date(timeIntervalSince1970: 0)
    ))
    let viewModel = DailyRankViewModel(
        gameCenter: fake, tabs: sudokuTabs(), initialAuthState: .authenticated(localPlayer)
    )
    await viewModel.onAppear()
    return viewModel
}

/// Empty (state 3): Friends scope, authorized, zero friends have played
/// today — `FakeGameCenterClient`'s default `leaderboardSlice` already has
/// zero entries, so no scripting is needed beyond selecting Friends.
@MainActor
private func makeEmptyFriendsViewModel() async -> DailyRankViewModel {
    let fake = FakeGameCenterClient()
    let viewModel = DailyRankViewModel(
        gameCenter: fake, tabs: sudokuTabs(), initialAuthState: .authenticated(localPlayer)
    )
    viewModel.selectedScope = .friends
    await viewModel.onAppear()
    return viewModel
}

@MainActor
@Suite("DailyRankView — #983 snapshots")
struct DailyRankViewTests {

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotPopulatedIPhoneLight() async {
        let viewModel = await makePopulatedViewModel()
        let host = hostingView(
            DailyRankView(viewModel: viewModel),
            size: SnapshotLayouts.iPhone, colorScheme: .light, sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "DailyRankView-iPhone-light-populated")
        }
        assertViewStructure(of: host, named: "DailyRankView-iPhone-light-populated", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotPopulatedIPhoneDark() async {
        let viewModel = await makePopulatedViewModel()
        let host = hostingView(
            DailyRankView(viewModel: viewModel),
            size: SnapshotLayouts.iPhone, colorScheme: .dark, sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "DailyRankView-iPhone-dark-populated")
        }
        assertViewStructure(of: host, named: "DailyRankView-iPhone-dark-populated", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotPopulatedMacLight() async {
        let viewModel = await makePopulatedViewModel()
        let host = hostingView(
            DailyRankView(viewModel: viewModel),
            size: SnapshotLayouts.mac, colorScheme: .light, sizeClass: .regular
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "DailyRankView-Mac-light-populated")
        }
        assertViewStructure(of: host, named: "DailyRankView-Mac-light-populated", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotPopulatedMacDark() async {
        let viewModel = await makePopulatedViewModel()
        let host = hostingView(
            DailyRankView(viewModel: viewModel),
            size: SnapshotLayouts.mac, colorScheme: .dark, sizeClass: .regular
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "DailyRankView-Mac-dark-populated")
        }
        assertViewStructure(of: host, named: "DailyRankView-Mac-dark-populated", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotEmptyFriendsIPhoneLight() async {
        let viewModel = await makeEmptyFriendsViewModel()
        let host = hostingView(
            DailyRankView(viewModel: viewModel),
            size: SnapshotLayouts.iPhone, colorScheme: .light, sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "DailyRankView-iPhone-light-emptyFriends")
        }
        assertViewStructure(of: host, named: "DailyRankView-iPhone-light-emptyFriends", record: SnapshotMode.recordMode)
    }
}
#endif
