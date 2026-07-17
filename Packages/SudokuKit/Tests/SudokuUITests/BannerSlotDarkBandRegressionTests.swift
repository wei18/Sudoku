// BannerSlotDarkBandRegressionTests — #851 deterministic repro.
//
// #866 replaced `LiveRouteFactory.themedBanner()`'s `BannerSlotView`
// `backgroundColor` from a stale `Color.secondary.opacity(0.12)`
// system-gray tint to `DefaultTheme().surface.background.resolved` — the
// SAME token the hub shell paints its own page background with. The CR's
// pixel analysis on the ORIGINAL audit screenshots found zero measurable
// row-mean variation in the reported 60-100% region, so the band itself was
// unconfirmed from those thumbnails (likely a rendering artifact that fooled
// the audit agent). This file is a from-scratch, deterministic repro
// instead of re-litigating those screenshots:
//
//   - the ad gate is forced OPEN by pre-resolving `AdGate.shouldShowBanner`
//     BEFORE constructing `BannerSlotView`, so the #723 layout-reservation
//     hint (`AdGate.lastKnownShouldShowBanner`) is already `true` when
//     `BannerSlotView.init` seeds its `@State shouldShow` — the slot then
//     renders on the FIRST synchronous layout pass, no async `.task` race;
//   - dark mode, iPhone size, via the existing `NSHostingView` harness
//     (`SnapshotConfig.swift`).
//
// Verdict (session 064a54f6, #851): the `postFix...` fixture below shows NO
// visible band — the themed background now matches the page background
// exactly. During investigation a second fixture reconstructed the STALE
// `Color.secondary.opacity(0.12)` literal (pre-#866) side by side and DID
// show a visible lighter rounded band at the same slot — confirming the
// report was real and #866 fixed it. That fixture was a synthetic
// reconstruction (no production call site references the stale color
// anymore), so it was not kept as a permanent test — only this ONE test
// pins the real regression contract per the CR's "zero coverage exists"
// finding.

import Foundation
import SnapshotTesting
import SwiftUI
import Testing

import MonetizationCore
import MonetizationTesting
import MonetizationUI
@testable import SudokuUI

import SudokuKitTesting
import SudokuPersistence

@MainActor
@Suite("BannerSlotView — dark-mode band regression (#851)")
struct BannerSlotDarkBandRegressionTests {

    nonisolated(unsafe) private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    /// Seed + synchronously pre-resolve an `AdGate` so `shouldShowBanner`
    /// returns `true` AND `lastKnownShouldShowBanner` (the #723 hint
    /// `BannerSlotView.init` reads) is already `true` before the view is
    /// constructed — see file header for why that matters for determinism.
    private func makeOpenAdGate() async -> AdGate {
        let store = FakeAdGateStateStore(
            initial: AdGateState(firstLaunchAt: Self.fixedDate.addingTimeInterval(-30 * 86_400))
        )
        let gate = AdGate(store: store)
        let allowed = await gate.shouldShowBanner(now: Self.fixedDate)
        #expect(allowed == true)
        #expect(gate.lastKnownShouldShowBanner == true)
        return gate
    }

    private func makeLoadedHubViewModel() async -> DailyHubViewModel {
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)))
        let viewModel = DailyHubViewModel(
            provider: provider,
            persistence: FakePersistence(),
            dateProvider: { Self.fixedDate }
        )
        await viewModel.bootstrap()
        return viewModel
    }

    #if canImport(AppKit)

    // MARK: - Post-#866: themed background — the real production path

    /// Mirrors `SudokuAppComposition.LiveRouteFactory.themedBanner()`
    /// exactly (same `backgroundColor` token). Pins the fix: the slot's
    /// background must equal the page's own background token so no seam is
    /// visible in dark mode, regardless of which hub mounts it.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func postFix_themedBackground_dailyHubDarkMode_bannerOpen_noBand() async {
        let gate = await makeOpenAdGate()
        let provider = FakeAdProvider()
        let viewModel = await makeLoadedHubViewModel()

        let view = DailyHubView(viewModel: viewModel) {
            BannerSlotView(
                adProvider: provider,
                adGate: gate,
                backgroundColor: DefaultTheme().surface.background.resolved
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        let host = hostingView(view, size: SnapshotLayouts.iPhone, colorScheme: .dark, sizeClass: .compact)
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "DailyHub-iPhone-dark-bannerOpen-postFix")
        }
    }

    #endif
}
