// MinesweeperHomeView — mode-card entry surface (#288 / #289, 2026-06-04).
//
// Thin wrapper over `GameShellUI.HomeScreen` (#410). The shared scaffold owns
// the `ScrollView { LazyVGrid(cards + RemoveAds) ; banner }` body, the column
// sizeClass logic, the mode card rendering, and the themed background.
// MinesweeperHomeView keeps only the MS-specific bits:
//   - the per-mode subtitles + tap routing (via `MinesweeperHomeViewModel.modeItems`),
//   - the per-card accessibility identifier namespace,
//   - the optional 5th "Remove Ads" card (MonetizationUI — kept app-side),
//   - the `MinesweeperBannerSlotView`,
//   - the navigation title + the monetization bootstrap `.task`.
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
            removeAdsCard: {
                if let controller = monetizationController, !controller.hasPurchasedRemoveAds {
                    Button {
                        Task { await controller.purchaseRemoveAds() }
                    } label: {
                        MinesweeperRemoveAdsCard(controller: controller)
                    }
                    .buttonStyle(.plain)
                    .disabled(controller.purchaseInFlight)
                    .accessibilityIdentifier("MinesweeperHomeView.RemoveAdsCard")
                }
            },
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
        .task {
            if let controller = monetizationController {
                await controller.bootstrap()
            }
        }
    }
}

/// 5th mode-card slot for Remove Ads. Mirrors `SudokuUI.RemoveAdsCard`:
/// tinted with `difficulty.medium` to signal commerce intent (not a difficulty
/// cue). Layout matches the shared `HomeModeCard` so the grid row height stays
/// consistent.
struct MinesweeperRemoveAdsCard: View {
    @Bindable var controller: MonetizationStateController
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(theme.difficulty.medium.resolved)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Remove Ads")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(theme.text.primary.resolved)
                Text("One-time purchase")
                    .font(.caption)
                    .foregroundStyle(theme.text.secondary.resolved)
            }
            Spacer()
            if controller.purchaseInFlight {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text(controller.removeAdsDisplayPrice)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(theme.difficulty.medium.resolved)
            }
        }
        .padding(16)
        .frame(minHeight: 72)
        .contentShape(Rectangle())
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Remove Ads \(controller.removeAdsDisplayPrice)")
        .accessibilityAddTraits(.isButton)
    }
}

#Preview("MinesweeperHome") {
    NavigationStack {
        MinesweeperHomeView(viewModel: MinesweeperHomeViewModel())
            .environment(\.theme, MinesweeperTheme())
    }
}
