// MinesweeperTodayTabViewTests — snapshot baselines for the Today tab's real
// root content: `GameAppKit.TodayTabHost` (resume pill) wrapping
// `MinesweeperDailyHubView`, exactly what `Live+TabRoots.swift` wires for
// `AppTab.today`.
//
// #1020: replaces the retired `MinesweeperHomeSnapshotTests` (HOME is gone;
// the marketing "01-home" slot now sources from this suite via
// `ASCScreenshotEmitTests.todayTabView()`) — same iPhone/iPad/Mac + dark +
// AX5 baseline matrix as SudokuKit's `TodayTabViewTests`, scoped down to the
// surface that actually still exists.
//
// #1024: `TodayTabHost` no longer owns a banner slot at all — it moved to
// the shared `tabViewBottomAccessory` (design.md §2.4, `BannerAccessoryView`
// in GameAppKit). The retired banner-region coverage below (`bannerVisible`)
// is now `BannerAccessoryViewTests` + the pre-existing `BannerSlotView`
// coverage — this suite no longer has any banner state to seed or assert on.

#if canImport(AppKit)
import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import MinesweeperUI

import GameAppKit
import GameCenterTesting
import MinesweeperEngine
import PersistenceTesting

@MainActor
@Suite("MinesweeperTodayTabView — GameAppKit.TodayTabHost + MinesweeperDailyHubView snapshots")
struct MinesweeperTodayTabViewTests {

    /// A fixed daily trio — all three card states exercised in the same
    /// frame. Hand-built (not date-derived) so the fixture is deterministic.
    /// Mirrors `MinesweeperDailyHubSnapshotTests.loadedTrio`.
    private static let loadedTrio: [MinesweeperDailyCard] = [
        MinesweeperDailyCard(
            entry: MinesweeperDailyEntry(puzzleId: "fixture-beginner", difficulty: .beginner, seed: 1),
            isCompleted: false,
            isFailed: false
        ),
        MinesweeperDailyCard(
            entry: MinesweeperDailyEntry(puzzleId: "fixture-intermediate", difficulty: .intermediate, seed: 2),
            isCompleted: true,
            isFailed: false
        ),
        MinesweeperDailyCard(
            entry: MinesweeperDailyEntry(puzzleId: "fixture-expert", difficulty: .expert, seed: 3),
            isCompleted: false,
            isFailed: true
        ),
    ]

    /// `TodayTabHost` wrapping a seeded Daily hub — the same composition
    /// `MinesweeperAppComposition.makeTabRoot(.today, …)` builds. #1024:
    /// `TodayTabHost` carries no banner slot / ad seams at all any more
    /// (moved to the shared `tabViewBottomAccessory`), so there is nothing
    /// left to seed here.
    private func todayTabHost() -> some View {
        let rootVM = MinesweeperRootViewModel(
            gameCenter: FakeGameCenterClient(),
            persistence: FakePersistence()
        )
        let dailyViewModel = MinesweeperDailyHubViewModel(path: .constant([]))
        dailyViewModel.setStateForTesting(.loaded(Self.loadedTrio))
        dailyViewModel.setPhase2PendingForTesting(false)
        return TodayTabHost(rootViewModel: rootVM) {
            MinesweeperDailyHubView(viewModel: dailyViewModel)
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotIPhoneLight() {
        let host = hostingView(
            todayTabHost(),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        assertUISnapshot(of: host, as: .image, named: "TodayTabView-iPhone-light", record: SnapshotMode.recordMode)
        assertViewStructure(of: host, named: "TodayTabView-iPhone-light", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotIPadLight() {
        let host = hostingView(
            todayTabHost(),
            size: SnapshotLayouts.iPad,
            colorScheme: .light,
            sizeClass: .regular
        )
        assertUISnapshot(of: host, as: .image, named: "TodayTabView-iPad-light", record: SnapshotMode.recordMode)
        assertViewStructure(of: host, named: "TodayTabView-iPad-light", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotMacLight() {
        let host = hostingView(
            todayTabHost(),
            size: SnapshotLayouts.mac,
            colorScheme: .light,
            sizeClass: .regular
        )
        assertUISnapshot(of: host, as: .image, named: "TodayTabView-Mac-light", record: SnapshotMode.recordMode)
        assertViewStructure(of: host, named: "TodayTabView-Mac-light", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotMacDark() {
        let host = hostingView(
            todayTabHost(),
            size: SnapshotLayouts.mac,
            colorScheme: .dark,
            sizeClass: .regular
        )
        assertUISnapshot(of: host, as: .image, named: "TodayTabView-Mac-dark", record: SnapshotMode.recordMode)
        assertViewStructure(of: host, named: "TodayTabView-Mac-dark", record: SnapshotMode.recordMode)
    }

    // #762 PR1 spec item E precedent (see the retired MinesweeperHomeSnapshotTests)
    // — AX5 smoke snapshot pinning `ScaledSpacing`'s visual effect. Same
    // headless-harness caveat applies: semantic `Font` sizes do not respond to
    // `dynamicTypeSize` overrides in this repo's `swift test` host, so this is
    // a spacing-scaling pin, not on-device AX5 truncation proof (that is
    // `interactive-simulator-ux-audit` territory).
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotAccessibility5IPhoneLight() {
        let host = hostingView(
            todayTabHost(),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact,
            dynamicTypeSize: .accessibility5
        )
        assertUISnapshot(
            of: host, as: .image, named: "TodayTabView-iPhone-light-accessibility5", record: SnapshotMode.recordMode
        )
        assertViewStructure(
            of: host, named: "TodayTabView-iPhone-light-accessibility5", record: SnapshotMode.recordMode
        )
    }

}
#endif
