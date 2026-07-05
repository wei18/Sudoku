// MinesweeperCompletionSnapshotTests — post-game result-surface baselines (#315).
//
// From #292 CR (peer of #303 / #308): MinesweeperCompletionView had 9 VM tests
// but no rendered baseline — its win-vs-loss hero and the conditional Retry /
// New Game CTAs were visually unverified. These baselines guard that surface
// across light + dark.
//
// #698: the leaderboard-slice fetch/present machine (`MinesweeperCompletionState`,
// `setStateForTesting(_:)`, the `GameCenterClient` dependency) was deleted from
// the VM — the completion popup has hardcoded `state: .hidden` since v2.6 and
// never rendered the leaderboard zone, so these baselines never depended on it
// (see the #587 note at the bottom). Seeding is now just `didWin`/`elapsedSeconds`.

#if canImport(AppKit)
import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import MinesweeperUI

@MainActor
@Suite("MinesweeperCompletionView — themed snapshots")
struct MinesweeperCompletionSnapshotTests {

    /// Build a Completion view backed by a VM with the given win/elapsed. `onRetry` /
    /// `onNewGame` are injected so the conditional CTAs render in the baselines
    /// (a win typically offers both).
    private func completionView(
        didWin: Bool,
        elapsedSeconds: Int = 65
    ) -> some View {
        let viewModel = MinesweeperCompletionViewModel(
            didWin: didWin,
            elapsedSeconds: elapsedSeconds,
            leaderboardId: MinesweeperLeaderboardID.easyDaily
        )
        return MinesweeperCompletionView(
            viewModel: viewModel,
            onClose: {}
        )
    }

    // MARK: - Re-opened solved daily (#386): hero OMITS the time row

    /// #386: re-viewing an already-solved daily has no stored elapsed (#284), so
    /// the route passes `showsElapsedTime: false` and the shared body OMITS the
    /// hero time row entirely — win hero, no time line. This baseline pins that
    /// no-time hero (contrast the `…win-loaded` baseline, which shows the "1:05"
    /// subtitle from the live-overlay `elapsedSeconds: 65` fixture).
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotWinLoadedNoElapsed_iPhone_light() {
        let viewModel = MinesweeperCompletionViewModel(
            didWin: true,
            elapsedSeconds: 0,
            leaderboardId: MinesweeperLeaderboardID.easyDaily
        )
        let view = MinesweeperCompletionView(
            viewModel: viewModel,
            onClose: {},
            showsElapsedTime: false
        )
        let host = hostingView(view, size: SnapshotLayouts.iPhone, colorScheme: .light)
        assertUISnapshot(of: host, as: .image, named: "Completion-iPhone-light-win-loaded-noElapsed", record: SnapshotMode.recordMode)
    }

    // MARK: - Win hero

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotWinLoaded_iPhone_light() {
        let host = hostingView(completionView(didWin: true), size: SnapshotLayouts.iPhone, colorScheme: .light)
        assertUISnapshot(of: host, as: .image, named: "Completion-iPhone-light-win-loaded", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotWinLoaded_iPad_light() {
        let host = hostingView(
            completionView(didWin: true),
            size: SnapshotLayouts.iPad,
            colorScheme: .light,
            sizeClass: .regular
        )
        assertUISnapshot(of: host, as: .image, named: "Completion-iPad-light-win-loaded", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotWinLoaded_iPhone_dark() {
        let host = hostingView(completionView(didWin: true), size: SnapshotLayouts.iPhone, colorScheme: .dark)
        assertUISnapshot(of: host, as: .image, named: "Completion-iPhone-dark-win-loaded", record: SnapshotMode.recordMode)
    }

    // MARK: - Loss hero (hero-only)

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotLoss_iPhone_light() {
        let host = hostingView(completionView(didWin: false), size: SnapshotLayouts.iPhone, colorScheme: .light)
        assertUISnapshot(of: host, as: .image, named: "Completion-iPhone-light-loss", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotLoss_iPhone_dark() {
        let host = hostingView(completionView(didWin: false), size: SnapshotLayouts.iPhone, colorScheme: .dark)
        assertUISnapshot(of: host, as: .image, named: "Completion-iPhone-dark-loss", record: SnapshotMode.recordMode)
    }

    // MARK: - Leaderboard-slice states were never snapshot-meaningful (#587 / #698)
    //
    // SDD-003 Epic 4 removed the leaderboard zone from the completion popup:
    // `MinesweeperCompletionView` mapped every leaderboard-fetch state to
    // `CompletionScreen(state: .hidden)`, leaving the VM machinery unrendered.
    // So `.loading` / `.failed` / `.loaded` rendered BYTE-IDENTICAL to the
    // `win-loaded` hero above — the old per-state baselines (loading/failed,
    // light+dark) asserted a distinction the view never made (false
    // confidence). They were removed in #587; #698 deleted the state machine
    // itself. `snapshotWinLoaded_*` remains the single guard that the popup
    // renders the hero with NO leaderboard zone.
}
#endif
