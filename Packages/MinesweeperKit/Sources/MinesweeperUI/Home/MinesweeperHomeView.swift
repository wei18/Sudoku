// MinesweeperHomeView — mode-card entry surface (#288 / #289, 2026-06-04).
//
// Thin wrapper over `GameShellUI.HomeScreen` (#410). The shared scaffold owns
// the `ScrollView { LazyVGrid(cards) ; banner }` body, the column sizeClass
// logic, the mode card rendering, and the themed background.
// MinesweeperHomeView keeps only the MS-specific bits:
//   - the per-mode subtitles + tap routing (via `MinesweeperHomeViewModel.modeItems`),
//   - the per-card accessibility identifier namespace,
//   - the `MinesweeperBannerSlotView`,
//   - the navigation title + the monetization bootstrap `.task`.
//
// SDD-003 Epic 7: "Remove Ads" home card removed; Settings Purchases entry preserved.
//
// #410: the erroneous "New Game" mode was removed — MS now shows exactly the
// 4 shared modes (Daily / Practice / Leaderboard / Settings), identical to Sudoku.
//
// Leaderboard (#291): presents Apple's native Game Center dashboard modally —
// a side effect, never a route (mirrors Sudoku #49).

public import SwiftUI
public import MonetizationCore
public import MonetizationUI
import GameShellUI

public struct MinesweeperHomeView: View {
    @Bindable private var viewModel: MinesweeperHomeViewModel
    private let adProvider: (any AdProvider)?
    private let adGate: AdGate?
    private let monetizationController: MonetizationStateController?
    // #441: tints the shared `MonetizationUI.BannerSlotView` from MS theme tokens.
    @Environment(\.theme) private var theme

    public init(
        viewModel: MinesweeperHomeViewModel,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil,
        monetizationController: MonetizationStateController? = nil
    ) {
        self.viewModel = viewModel
        self.adProvider = adProvider
        self.adGate = adGate
        self.monetizationController = monetizationController
    }

    public var body: some View {
        HomeScreen(
            items: viewModel.modeItems,
            cardAccessibilityIdentifier: { mode in "MinesweeperHomeView.\(mode.rawValue)Card" },
            banner: {
                if let adProvider, let adGate {
                    BannerSlotView(
                        adProvider: adProvider,
                        adGate: adGate,
                        // Live provider conforms to `BannerViewProviding`; fakes /
                        // macOS NoopAdProvider don't → nil → honest fallback. The
                        // cast keeps MinesweeperUI free of an AdsAdMob import (§9.1).
                        bannerHost: adProvider as? any BannerViewProviding,
                        backgroundColor: theme.surface.placeholder.resolved,
                        progressTint: theme.accent.primary.resolved,
                        captionColor: theme.text.secondary.resolved,
                        dismissTint: theme.accent.muted.resolved.opacity(0.7)
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        )
        .navigationTitle("Minesweeper")
        // #513: shown when the leaderboard card is tapped with GC signed out.
        .alert(
            "Sign in to Game Center",
            isPresented: $viewModel.showGameCenterSignedOutAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Sign in to Game Center to compare with others.")
        }
        .task {
            if let controller = monetizationController {
                await controller.bootstrap()
            }
        }
    }
}

#Preview("MinesweeperHome") {
    NavigationStack {
        MinesweeperHomeView(viewModel: MinesweeperHomeViewModel())
            .environment(\.theme, MinesweeperTheme())
    }
}
