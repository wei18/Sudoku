// MinesweeperTodayTabViewTests — snapshot baselines for the Today tab's real
// root content: `GameAppKit.TodayTabHost` (resume pill + banner + the C-33
// ATT anchor) wrapping `MinesweeperDailyHubView`, exactly what
// `Live+TabRoots.swift` wires for `AppTab.today`.
//
// #1020: replaces the retired `MinesweeperHomeSnapshotTests` (HOME is gone;
// the marketing "01-home" slot now sources from this suite via
// `ASCScreenshotEmitTests.todayTabView()`) — same iPhone/iPad/Mac + dark +
// AX5 baseline matrix as SudokuKit's `TodayTabViewTests`, scoped down to the
// surface that actually still exists.

#if canImport(AppKit)
import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import MinesweeperUI

import GameAppKit
import GameCenterTesting
import MinesweeperEngine
import MonetizationCore
import MonetizationTesting
import MonetizationUI
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
    /// `MinesweeperAppComposition.makeTabRoot(.today, …)` builds.
    private func todayTabHost() -> some View {
        let rootVM = MinesweeperRootViewModel(
            gameCenter: FakeGameCenterClient(),
            persistence: FakePersistence()
        )
        let dailyViewModel = MinesweeperDailyHubViewModel(path: .constant([]))
        dailyViewModel.setStateForTesting(.loaded(Self.loadedTrio))
        dailyViewModel.setPhase2PendingForTesting(false)
        return TodayTabHost(
            rootViewModel: rootVM,
            adProvider: FakeAdProvider(),
            adGate: AdGate(store: FakeAdGateStateStore(
                initial: AdGateState(
                    firstLaunchAt: Date(timeIntervalSince1970: 0),
                    hasPurchasedRemoveAds: true
                )
            )),
            attPrimer: ATTPrimerCoordinator(
                isNotDetermined: { false },
                requestSystemPrompt: {}
            )
        ) {
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
