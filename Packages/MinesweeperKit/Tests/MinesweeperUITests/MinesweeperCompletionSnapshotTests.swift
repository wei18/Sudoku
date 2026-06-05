// MinesweeperCompletionSnapshotTests — post-game result-surface baselines (#315).
//
// From #292 CR (peer of #303 / #308): MinesweeperCompletionView had 9 VM tests
// but no rendered baseline — its win-vs-loss hero, the conditional Retry /
// New Game CTAs, and the four content slice states (loading / loaded /
// unauthenticated / failed) were visually unverified. These baselines guard
// that surface across light + dark.
//
// Seam (#315): none added — the VM already exposes
// `MinesweeperCompletionViewModel.setStateForTesting(_:)` (the #292 degrade-
// state seam), which sets the slice state AND latches `hasBootstrapped`, so the
// view's `.task { bootstrap() }` is a no-op and the seeded state survives
// NSHostingView capture. Mirrors Sudoku's CompletionViewTests.

#if canImport(AppKit)
import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import MinesweeperUI

import GameCenterClient
import GameCenterTesting

@MainActor
@Suite("MinesweeperCompletionView — themed snapshots")
struct MinesweeperCompletionSnapshotTests {

    /// A deterministic local-player-centred slice (fixed `fetchedAt`, hand-built
    /// entries) — mirrors the VM-test fixture so the `.loaded` baseline matches
    /// the real leaderboard-section layout.
    private static let sampleSlice = LeaderboardSlice(
        leaderboardId: MinesweeperLeaderboardID.easyDaily,
        scope: .globalAllTime,
        entries: [
            LeaderboardEntry(rank: 1, player: PlayerSummary(teamPlayerId: "P1", displayName: "alice"), score: 41),
            LeaderboardEntry(rank: 2, player: PlayerSummary(teamPlayerId: "P2", displayName: "bob"), score: 55),
            LeaderboardEntry(rank: 3, player: PlayerSummary(teamPlayerId: "P3", displayName: "carol"), score: 73),
        ],
        totalPlayerCount: 900,
        fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    /// Build a Completion view backed by a VM seeded to `state`. `didWin` drives
    /// the hero; `onRetry` / `onNewGame` are injected so the conditional CTAs
    /// render in the baselines (a win typically offers both).
    private func completionView(
        didWin: Bool,
        elapsedSeconds: Int = 65,
        state: MinesweeperCompletionState
    ) -> some View {
        let viewModel = MinesweeperCompletionViewModel(
            didWin: didWin,
            elapsedSeconds: elapsedSeconds,
            leaderboardId: MinesweeperLeaderboardID.easyDaily,
            gameCenter: FakeGameCenterClient()
        )
        viewModel.setStateForTesting(state)
        return MinesweeperCompletionView(
            viewModel: viewModel,
            onNewGame: {},
            onRetry: {}
        )
    }

    // MARK: - Win hero + loaded leaderboard slice

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotWinLoaded_iPhone_light() {
        assertUISnapshot(
            of: hostingView(
                completionView(didWin: true, state: .loaded(Self.sampleSlice)),
                size: SnapshotLayouts.iPhone,
                colorScheme: .light
            ),
            as: .tolerantImage,
            named: "Completion-iPhone-light-win-loaded",
            record: SnapshotMode.recordMode
        )
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotWinLoaded_iPhone_dark() {
        assertUISnapshot(
            of: hostingView(
                completionView(didWin: true, state: .loaded(Self.sampleSlice)),
                size: SnapshotLayouts.iPhone,
                colorScheme: .dark
            ),
            as: .tolerantImage,
            named: "Completion-iPhone-dark-win-loaded",
            record: SnapshotMode.recordMode
        )
    }

    // MARK: - Loss hero (hero-only, unauthenticated affordance)

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotLoss_iPhone_light() {
        assertUISnapshot(
            of: hostingView(
                completionView(didWin: false, state: .unauthenticated),
                size: SnapshotLayouts.iPhone,
                colorScheme: .light
            ),
            as: .tolerantImage,
            named: "Completion-iPhone-light-loss",
            record: SnapshotMode.recordMode
        )
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotLoss_iPhone_dark() {
        assertUISnapshot(
            of: hostingView(
                completionView(didWin: false, state: .unauthenticated),
                size: SnapshotLayouts.iPhone,
                colorScheme: .dark
            ),
            as: .tolerantImage,
            named: "Completion-iPhone-dark-loss",
            record: SnapshotMode.recordMode
        )
    }

    // MARK: - Slice states (loading / failed) — win hero

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotLoading_iPhone_light() {
        assertUISnapshot(
            of: hostingView(
                completionView(didWin: true, state: .loading),
                size: SnapshotLayouts.iPhone,
                colorScheme: .light
            ),
            as: .tolerantImage,
            named: "Completion-iPhone-light-loading",
            record: SnapshotMode.recordMode
        )
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotFailed_iPhone_light() {
        assertUISnapshot(
            of: hostingView(
                completionView(didWin: true, state: .failed("network offline")),
                size: SnapshotLayouts.iPhone,
                colorScheme: .light
            ),
            as: .tolerantImage,
            named: "Completion-iPhone-light-failed",
            record: SnapshotMode.recordMode
        )
    }
}
#endif
