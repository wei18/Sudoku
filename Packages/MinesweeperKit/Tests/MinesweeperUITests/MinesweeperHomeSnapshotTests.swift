// MinesweeperHomeSnapshotTests — mode-card entry-surface baselines (#303).
//
// From #288 CR: the Home surface (5 mode cards, MS-theme-tinted, 1-col compact /
// 2-col regular) had VM navigation tests but no rendered baseline. These guard
// theme + layout drift on the most-seen screen.
//
// No production seam needed: `MinesweeperHomeView(viewModel:)` with no
// ad/monetization injectors renders the static 5-card grid (no banner, no
// Remove-Ads card) and its `.task` is a no-op when `monetizationController` is
// nil — so the surface is deterministic at NSHostingView capture without any
// pre-seeding. Mirrors the harness in MinesweeperBoardSnapshotTests.

#if canImport(AppKit)
import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import MinesweeperUI

@MainActor
@Suite("MinesweeperHomeView — themed snapshots")
struct MinesweeperHomeSnapshotTests {

    /// The Home surface as the live root mounts it: just the view model, no ad
    /// provider / monetization controller, wrapped in a NavigationStack so the
    /// `.navigationTitle` chrome renders.
    private func homeView() -> some View {
        NavigationStack {
            MinesweeperHomeView(viewModel: MinesweeperHomeViewModel())
        }
    }

    // MARK: - Compact (iPhone, 1-column)

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotHome_iPhone_light() {
        let host = hostingView(
            homeView(),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        assertUISnapshot(of: host, as: .tolerantImage, named: "Home-iPhone-light-compact", record: SnapshotMode.recordMode)
        assertViewStructure(of: host, named: "Home-iPhone-light-compact", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotHome_iPhone_dark() {
        let host = hostingView(
            homeView(),
            size: SnapshotLayouts.iPhone,
            colorScheme: .dark,
            sizeClass: .compact
        )
        assertUISnapshot(of: host, as: .tolerantImage, named: "Home-iPhone-dark-compact", record: SnapshotMode.recordMode)
        assertViewStructure(of: host, named: "Home-iPhone-dark-compact", record: SnapshotMode.recordMode)
    }

    // MARK: - iPad 13" (regular, 1032×1376 pt)

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotHome_iPad_light() {
        let host = hostingView(
            homeView(),
            size: SnapshotLayouts.iPad,
            colorScheme: .light,
            sizeClass: .regular
        )
        assertUISnapshot(of: host, as: .tolerantImage, named: "Home-iPad-light-regular", record: SnapshotMode.recordMode)
        assertViewStructure(of: host, named: "Home-iPad-light-regular", record: SnapshotMode.recordMode)
    }

    // MARK: - Regular (Mac width, 2-column)

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotHome_regular_light() {
        let host = hostingView(
            homeView(),
            size: SnapshotLayouts.mac,
            colorScheme: .light,
            sizeClass: .regular
        )
        assertUISnapshot(of: host, as: .tolerantImage, named: "Home-mac-light-regular", record: SnapshotMode.recordMode)
        assertViewStructure(of: host, named: "Home-mac-light-regular", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotHome_regular_dark() {
        let host = hostingView(
            homeView(),
            size: SnapshotLayouts.mac,
            colorScheme: .dark,
            sizeClass: .regular
        )
        assertUISnapshot(of: host, as: .tolerantImage, named: "Home-mac-dark-regular", record: SnapshotMode.recordMode)
        assertViewStructure(of: host, named: "Home-mac-dark-regular", record: SnapshotMode.recordMode)
    }
}
#endif
