// DailyRankViewTests — snapshot coverage for the shared #983 Daily Rank
// screen, Minesweeper-parameterized (Beginner/Intermediate/Expert tabs, MS
// leaderboard ids). Mirrors SudokuKit's DailyRankViewTests.swift (same
// FakeGameCenterClient / hostingView / assertViewStructure harness — no
// shared test-helper target, so the two suites intentionally duplicate this
// shape) — never a live `authenticateHandler` (#766).

#if canImport(AppKit)
import AppKit
import Foundation
import GameAppKit
import GameCenterClient
import GameCenterTesting
import SnapshotTesting
import SwiftUI
import Testing
@testable import MinesweeperUI

private let localPlayer = PlayerSummary(teamPlayerId: "P0001", displayName: "TestSweeper")

@MainActor
private func minesweeperTabs() -> [DailyRankTab] {
    [
        DailyRankTab(id: "beginner", titleKey: "Beginner", leaderboardId: "com.wei18.minesweeper.leaderboard.easy.daily.v1"),
        DailyRankTab(id: "intermediate", titleKey: "Intermediate", leaderboardId: "com.wei18.minesweeper.leaderboard.medium.daily.v1"),
        DailyRankTab(id: "expert", titleKey: "Expert", leaderboardId: "com.wei18.minesweeper.leaderboard.hard.daily.v1")
    ]
}

/// Populated: 3 entries, local player at rank 2 (inside the top slice).
@MainActor
private func makePopulatedViewModel() async -> DailyRankViewModel {
    let fake = FakeGameCenterClient()
    await fake.setLeaderboardSlice(LeaderboardSlice(
        leaderboardId: "com.wei18.minesweeper.leaderboard.easy.daily.v1",
        scope: .globalAllTime,
        entries: [
            LeaderboardEntry(rank: 1, player: PlayerSummary(teamPlayerId: "P0777", displayName: "Nadia"), score: 41),
            LeaderboardEntry(rank: 2, player: localPlayer, score: 58),
            LeaderboardEntry(rank: 3, player: PlayerSummary(teamPlayerId: "P0333", displayName: "Owen"), score: 63)
        ],
        totalPlayerCount: 3,
        fetchedAt: Date(timeIntervalSince1970: 0)
    ))
    let viewModel = DailyRankViewModel(
        gameCenter: fake, tabs: minesweeperTabs(), initialAuthState: .authenticated(localPlayer)
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
        gameCenter: fake, tabs: minesweeperTabs(), initialAuthState: .authenticated(localPlayer)
    )
    viewModel.selectedScope = .friends
    await viewModel.onAppear()
    return viewModel
}

@MainActor
@Suite("DailyRankView — #983 snapshots (Minesweeper)")
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
