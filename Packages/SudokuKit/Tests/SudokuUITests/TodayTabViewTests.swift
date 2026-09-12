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
    /// composition `SudokuAppComposition.makeTabRoot(.today, …)` builds
    /// (`DailyHubView` itself takes no `banner:` here — `TodayTabHost` is the
    /// ONE banner slot for the whole tab; see the CR fix note on
    /// `Live+TabRoots.swift`). Injects `BannerSessionModel.disabled`, so every
    /// baseline below has the banner region collapsed — `bannerVisible` below
    /// is the one fixture that shows the banner region.
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
        return TodayTabHost(rootViewModel: rootVM) {
            DailyHubView(viewModel: dailyViewModel)
        }
        .environment(\.bannerSession, .disabled)
    }

    /// Deterministic stand-in for the live `ProgressView` spinner (#732,
    /// mirrors `BoardViewBannerTests`) — same static ring look, no
    /// animation-frame dependency, so this baseline isn't timing-sensitive.
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
    /// on the very first layout and stays in its loading state (mirrors
    /// `BoardViewBannerTests`).
    private func todayTabHostWithVisibleBanner() async -> some View {
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
            DailyHubView(viewModel: dailyViewModel)
        }
        .environment(\.bannerSlotLoadingPreview, deterministicBannerLoadingPreview)
        .environment(\.bannerSession, session)
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
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "TodayTabView-iPhone-light-bannerVisible")
        }
        assertViewStructure(of: host, named: "TodayTabView-iPhone-light-bannerVisible", record: SnapshotMode.recordMode)
    }
}
