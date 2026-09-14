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
    /// `MinesweeperAppComposition.makeTabRoot(.today, …)` builds
    /// (`MinesweeperDailyHubView` itself takes no `banner:` here —
    /// `TodayTabHost` is the ONE banner slot for the whole tab; see the CR
    /// fix note on `Live+TabRoots.swift`). Injects `BannerSessionModel.disabled`,
    /// so every baseline below has the banner region collapsed —
    /// `bannerVisible` below is the one fixture that shows the banner region.
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
        .environment(\.bannerSession, .disabled)
    }

    /// Deterministic stand-in for the live `ProgressView` spinner (#732,
    /// mirrors `BoardViewBannerTests`/SudokuKit's `TodayTabViewTests`) — same
    /// static ring look, no animation-frame dependency.
    private var deterministicBannerLoadingPreview: AnyView {
        AnyView(
            Circle()
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .frame(width: 16, height: 16)
        )
    }

    /// Same composition as `todayTabHost()` but with a started session over an
    /// OPEN gate (`hasPurchasedRemoveAds: false`, 30 days post-launch) and a
    /// readiness-held fake provider, so the banner's 50pt rect reserves space
    /// on the very first layout and stays in its loading state.
    private func todayTabHostWithVisibleBanner() async -> some View {
        let rootVM = MinesweeperRootViewModel(
            gameCenter: FakeGameCenterClient(),
            persistence: FakePersistence()
        )
        let dailyViewModel = MinesweeperDailyHubViewModel(path: .constant([]))
        dailyViewModel.setStateForTesting(.loaded(Self.loadedTrio))
        dailyViewModel.setPhase2PendingForTesting(false)
        let session = BannerSessionModel(
            adProvider: FakeAdProvider(readinessHeld: true),
            adGate: AdGate(store: FakeAdGateStateStore(
                initial: AdGateState(
                    firstLaunchAt: Date().addingTimeInterval(-30 * 86_400),
                    hasPurchasedRemoveAds: false
                )
            ))
        )
        await session.start()
        return TodayTabHost(rootViewModel: rootVM) {
            MinesweeperDailyHubView(viewModel: dailyViewModel)
        }
        .environment(\.bannerSlotLoadingPreview, deterministicBannerLoadingPreview)
        .environment(\.bannerSession, session)
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

    // MARK: - Banner region coverage (CR follow-up)
    //
    // Every baseline above seeds the gate CLOSED, so none of them exercises
    // `TodayTabHost`'s own banner slot — this is the marketing "01-home"
    // source, so a banner regression there would ship unnoticed. This one
    // fixture opens the gate (mirrors `BoardViewBannerTests`'s convention).

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotIPhoneLightBannerVisible() async {
        let host = hostingView(
            await todayTabHostWithVisibleBanner(),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        assertUISnapshot(
            of: host, as: .image, named: "TodayTabView-iPhone-light-bannerVisible", record: SnapshotMode.recordMode
        )
        assertViewStructure(
            of: host, named: "TodayTabView-iPhone-light-bannerVisible", record: SnapshotMode.recordMode
        )
    }
}
#endif
