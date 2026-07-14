// MinesweeperHomeSnapshotTests — mode-card entry-surface baselines (#303).
//
// From #288 CR: the Home surface (4 mode cards, MS-theme-tinted, 1-col compact /
// 2-col regular) had VM navigation tests but no rendered baseline. These guard
// theme + layout drift on the most-seen screen.
//
// #572 SDD-005 Pillar C: migrated from `MinesweeperHomeView(viewModel:)` to
// the shared `GameHomeView(viewModel:rootViewModel:title:adProvider:adGate:attPrimer:)`.
// Pixel content is byte-identical (same HomeScreen scaffold, same MS theme, same
// 4-mode card layout). Only the view-structure `.txt` baseline changes:
// `MinesweeperUI.MinesweeperHomeView` → `GameAppKit.GameHomeView` (same as the
// Sudoku #557 migration). PNGs must NOT change.

#if canImport(AppKit)
import Foundation
import GameAppKit
import GameCenterTesting
import GameShellUI
import MonetizationCore
import MonetizationTesting
import MonetizationUI
import PersistenceTesting
import SnapshotTesting
import SwiftUI
import Testing
@testable import MinesweeperUI

/// Build a minimal rootVM + GameHomeViewModel with MS defaults.
@MainActor
private func makeMSHomeViewModels() -> (
    rootVM: MinesweeperRootViewModel,
    homeVM: GameHomeViewModel<AppRoute>
) {
    let rootVM = MinesweeperRootViewModel(
        gameCenter: FakeGameCenterClient(),
        persistence: FakePersistence()
    )
    let homeVM = GameHomeViewModel(
        rootViewModel: rootVM,
        homeModes: minesweeperHomeModes,
        // #773: mirrors MinesweeperAppComposition.live()'s statsRoute so the
        // Home snapshots pin the secondary-weight Statistics entry.
        statsRoute: .stats
    )
    return (rootVM, homeVM)
}

/// MS per-mode subtitle copy — byte-identical to the former
/// `MinesweeperHomeMode.subtitleKey` private extension.
@MainActor
private let minesweeperHomeModes: [HomeMode: HomeModeContent<AppRoute>] = [
    .daily: HomeModeContent<AppRoute>(subtitleKey: "3 boards today", route: .daily),
    .practice: HomeModeContent<AppRoute>(subtitleKey: "All difficulties", route: .practice),
    .leaderboard: HomeModeContent<AppRoute>(subtitleKey: "Best times"),
    .settings: HomeModeContent<AppRoute>(subtitleKey: "Purchases / about", route: .settings)
]

@MainActor
@Suite("MinesweeperHomeView — themed snapshots")
struct MinesweeperHomeSnapshotTests {

    /// The Home surface as the live root mounts it: just the view model, no ad
    /// provider / monetization controller, wrapped in a NavigationStack so the
    /// `.navigationTitle` chrome renders.
    private func homeView() -> some View {
        let (rootVM, homeVM) = makeMSHomeViewModels()
        return NavigationStack {
            GameHomeView(
                viewModel: homeVM,
                rootViewModel: rootVM,
                title: "Minesweeper",
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
            )
        }
        .environment(\.theme, MinesweeperTheme())
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
        assertUISnapshot(of: host, as: .image, named: "Home-iPhone-light-compact", record: SnapshotMode.recordMode)
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
        assertUISnapshot(of: host, as: .image, named: "Home-iPhone-dark-compact", record: SnapshotMode.recordMode)
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
        assertUISnapshot(of: host, as: .image, named: "Home-iPad-light-regular", record: SnapshotMode.recordMode)
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
        assertUISnapshot(of: host, as: .image, named: "Home-mac-light-regular", record: SnapshotMode.recordMode)
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
        assertUISnapshot(of: host, as: .image, named: "Home-mac-dark-regular", record: SnapshotMode.recordMode)
        assertViewStructure(of: host, named: "Home-mac-dark-regular", record: SnapshotMode.recordMode)
    }
}
#endif
