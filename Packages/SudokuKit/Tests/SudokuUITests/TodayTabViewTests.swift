// TodayTabViewTests — snapshot baselines for the Today tab's real root
// content: `GameAppKit.TodayTabHost` (resume pill + banner + the C-33 ATT
// anchor) wrapping `DailyHubView`, exactly what `Live+TabRoots.swift` wires
// for `AppTab.today`.
//
// #1020: replaces the retired `HomeViewTests` (HOME is gone; the marketing
// "01-home" slot now sources from this suite via `ASCScreenshotEmitTests
// .todayTabView()`) — same iPhone/iPad/Mac + dark + AX5 baseline matrix,
// scoped down to the surface that actually still exists.

import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import SudokuUI

import GameAppKit
import GameCenterTesting
import MonetizationCore
import MonetizationTesting
import MonetizationUI
import Persistence
import SudokuKitTesting
import SudokuPersistence

@MainActor
@Suite("TodayTabView — GameAppKit.TodayTabHost + DailyHubView snapshots")
struct TodayTabViewTests {

    nonisolated(unsafe) private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    /// `TodayTabHost` wrapping a bootstrapped `DailyHubView` — the same
    /// composition `SudokuAppComposition.makeTabRoot(.today, …)` builds.
    private func todayTabHost() async -> some View {
        let rootVM = RootViewModel(
            gameCenter: FakeGameCenterClient(),
            persistence: FakePersistence()
        )
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)))
        let dailyViewModel = DailyHubViewModel(
            provider: provider,
            persistence: FakePersistence(completedDailyIds: []),
            dateProvider: { Self.fixedDate }
        )
        await dailyViewModel.bootstrap()
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
            DailyHubView(viewModel: dailyViewModel)
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotIPhoneLight() async {
        let host = hostingView(
            await todayTabHost(),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "TodayTabView-iPhone-light")
        }
        assertViewStructure(of: host, named: "TodayTabView-iPhone-light", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotIPadLight() async {
        let host = hostingView(
            await todayTabHost(),
            size: SnapshotLayouts.iPad,
            colorScheme: .light,
            sizeClass: .regular
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "TodayTabView-iPad-light")
        }
        assertViewStructure(of: host, named: "TodayTabView-iPad-light", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotMacLight() async {
        let host = hostingView(
            await todayTabHost(),
            size: SnapshotLayouts.mac,
            colorScheme: .light,
            sizeClass: .regular
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "TodayTabView-Mac-light")
        }
        assertViewStructure(of: host, named: "TodayTabView-Mac-light", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotMacDark() async {
        let host = hostingView(
            await todayTabHost(),
            size: SnapshotLayouts.mac,
            colorScheme: .dark,
            sizeClass: .regular
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "TodayTabView-Mac-dark")
        }
        assertViewStructure(of: host, named: "TodayTabView-Mac-dark", record: SnapshotMode.recordMode)
    }

    // #762 PR1 spec item E precedent (see the retired HomeViewTests) — AX5
    // smoke snapshot pinning `ScaledSpacing`'s visual effect. Same headless-
    // harness caveat applies: semantic `Font` sizes do not respond to
    // `dynamicTypeSize` overrides in this repo's `swift test` host, so this
    // is a spacing-scaling pin, not on-device AX5 truncation proof (that is
    // `interactive-simulator-ux-audit` territory).
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotAccessibility5IPhoneLight() async {
        let host = hostingView(
            await todayTabHost(),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact,
            dynamicTypeSize: .accessibility5
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "TodayTabView-iPhone-light-accessibility5")
        }
        assertViewStructure(of: host, named: "TodayTabView-iPhone-light-accessibility5", record: SnapshotMode.recordMode)
    }
}
