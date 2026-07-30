// CompletionViewTests — 2 hero/mistake-row snapshots (#698: leaderboard-state
// snapshots removed, the leaderboard zone never rendered — both `.loaded` and
// `.noLeaderboard` degraded to the same hero-only surface, so they carried no
// distinct visual coverage beyond mistakeCount value).

import Foundation
import GameShellUI
import SnapshotTesting
import SwiftUI
import Testing
@testable import SudokuUI

import SudokuKitTesting

@MainActor
@Suite("CompletionView — hero snapshots")
struct CompletionViewTests {

    private func makeViewModel(mistakeCount: Int = 2) -> CompletionViewModel {
        CompletionViewModel(
            puzzleId: "2026-05-19-easy",
            elapsedSeconds: 251,
            mistakeCount: mistakeCount,
            leaderboardId: "com.wei18.sudoku.leaderboard.easy.daily.v1"
        )
    }

    // MARK: - Snapshots (2 PNGs)

    #if canImport(AppKit)
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshot_authenticatedLoaded_iPhoneLight() async {
        let viewModel = makeViewModel()
        let host = hostingView(
            // The hero-reveal `.onAppear` never fires on this off-screen
            // host — see `completionHeroSkipsReveal`'s doc comment.
            CompletionView(viewModel: viewModel)
                .environment(\.completionHeroSkipsReveal, true),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "Completion-iPhone-light-loaded")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshot_authenticatedLoaded_iPadLight() async {
        let viewModel = makeViewModel()
        let host = hostingView(
            // The hero-reveal `.onAppear` never fires on this off-screen
            // host — see `completionHeroSkipsReveal`'s doc comment.
            CompletionView(viewModel: viewModel)
                .environment(\.completionHeroSkipsReveal, true),
            size: SnapshotLayouts.iPad,
            colorScheme: .light,
            sizeClass: .regular
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "Completion-iPad-light-loaded")
        }
    }

    // #587 / #698: removed `snapshot_unauthenticated_iPhoneLight_zhTW` and the
    // per-leaderboard-state variants. SDD-003 Epic 4 already mapped every
    // leaderboard state to `CompletionScreen(state: .hidden)` (byte-identical
    // rendering); #698 deleted the state machine itself. `.noLeaderboard`'s
    // distinct mistakeCount: 0 hero styling is still covered below.

    // #383: Practice solve (nil leaderboard). mistakeCount: 0 exercises the
    // hero's mistake-row "success" tint (vs. mistakeCount: 2 above) — the only
    // remaining visual distinction between these two fixtures now that the
    // leaderboard zone never renders.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshot_noLeaderboard_iPhoneLight() async {
        let viewModel = CompletionViewModel(
            puzzleId: "practice-7Z9K-medium",
            elapsedSeconds: 251,
            mistakeCount: 0,
            leaderboardId: nil
        )
        let host = hostingView(
            // The hero-reveal `.onAppear` never fires on this off-screen
            // host — see `completionHeroSkipsReveal`'s doc comment.
            CompletionView(viewModel: viewModel)
                .environment(\.completionHeroSkipsReveal, true),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "Completion-iPhone-light-noLeaderboard")
        }
    }

    // #587: removed `snapshot_fetchFailed_iPhoneLight` — the popup hides the
    // leaderboard zone (Epic 4, `state: .hidden`), so `.failed` rendered
    // byte-identical to the `.loaded` baseline above; the per-state variant
    // asserted a distinction the view no longer makes (false confidence).
    #endif
}
