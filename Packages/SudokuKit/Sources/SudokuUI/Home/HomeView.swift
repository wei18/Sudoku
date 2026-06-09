// HomeView — Sudoku's 4 mode cards (Daily / Practice / Leaderboard / Settings).
//
// Thin wrapper over `GameShellUI.HomeScreen` (#410). The shared scaffold owns
// the `ScrollView { header ; LazyVGrid(cards + RemoveAds) ; banner }` body, the
// column sizeClass logic, the mode card rendering, and the themed background.
// HomeView keeps only the Sudoku-specific bits:
//   - the per-mode subtitles + tap routing (via `HomeViewModel.modeItems`),
//   - the optional 5th "Remove Ads" card (MonetizationUI — kept app-side so it
//     never leaks into GameShellUI),
//   - the banner slot (`BannerSlotView` — AdProvider / AdGate live here),
//   - the navigation title + the monetization bootstrap `.task`.
//
// #387: an optional `header` slot renders as the first child INSIDE the scroll
// region (RootView passes its ResumePill here so the pill scrolls with the mode
// cards). RootView still owns the resume-candidate state + tap closure.

public import MonetizationCore
public import MonetizationUI
public import SwiftUI
import GameShellUI

public struct HomeView<Header: View>: View {
    @Bindable private var viewModel: HomeViewModel
    private let adProvider: (any AdProvider)?
    private let adGate: AdGate?
    private let monetizationController: MonetizationStateController?
    // #371 / #195: ATT pre-prompt trigger, forwarded to the BannerSlotView so
    // the priming sheet is offered at the first ad-relevant moment (gate open).
    private let attPrimer: ATTPrimerCoordinator?
    // #387: optional header rendered as the first child INSIDE the scroll
    // region. RootView passes its ResumePill here so the pill scrolls with
    // the mode cards instead of sitting pinned above HomeView's ScrollView.
    private let header: Header

    // #441: tints the shared `MonetizationUI.BannerSlotView` from theme tokens.
    @Environment(\.theme) private var theme

    public init(
        viewModel: HomeViewModel,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil,
        monetizationController: MonetizationStateController? = nil,
        attPrimer: ATTPrimerCoordinator? = nil,
        @ViewBuilder header: () -> Header = { EmptyView() }
    ) {
        self.viewModel = viewModel
        self.adProvider = adProvider
        self.adGate = adGate
        self.monetizationController = monetizationController
        self.attPrimer = attPrimer
        self.header = header()
    }

    public var body: some View {
        HomeScreen(
            items: viewModel.modeItems,
            header: { header },
            removeAdsCard: {
                if let controller = monetizationController, !controller.hasPurchasedRemoveAds {
                    Button {
                        Task { await controller.purchaseRemoveAds() }
                    } label: {
                        RemoveAdsCard(controller: controller)
                    }
                    .buttonStyle(.plain)
                    .disabled(controller.purchaseInFlight)
                    .accessibilityIdentifier("HomeView.RemoveAdsCard")
                }
            },
            banner: {
                if let adProvider, let adGate {
                    bannerSlot(adProvider: adProvider, adGate: adGate)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }
        )
        .navigationTitle("Sudoku")
        .task {
            if let controller = monetizationController {
                await controller.bootstrap()
            }
        }
    }

    /// Themed shared `MonetizationUI.BannerSlotView` (#441). The live provider
    /// conforms to `BannerViewProviding`; fakes / macOS NoopAdProvider don't →
    /// nil → honest fallback. The cast keeps SudokuUI free of an AdsAdMob
    /// import (§9.1). ATT priming (#371 / #195) is offered at the first
    /// ad-relevant moment (gate open) via `onAdContext`.
    private func bannerSlot(adProvider: any AdProvider, adGate: AdGate) -> some View {
        var onAdContext: (@Sendable () async -> Void)?
        if let primer = attPrimer {
            onAdContext = { await primer.maybePresentOnAdContext() }
        }
        return BannerSlotView(
            adProvider: adProvider,
            adGate: adGate,
            bannerHost: adProvider as? any BannerViewProviding,
            onAdContext: onAdContext,
            backgroundColor: theme.surface.placeholder.resolved,
            progressTint: theme.accent.primary.resolved,
            captionColor: theme.text.secondary.resolved,
            dismissTint: theme.accent.muted.resolved.opacity(0.7)
        )
    }
}

/// 5th mode-card slot for Remove Ads. Tinted with `difficulty.medium` to
/// signal commerce intent (per v2.3.6 brief: not a difficulty cue; reuses
/// the medium clay accent token from PR #78). Layout mirrors the shared
/// `HomeModeCard` so the grid row height stays consistent.
struct RemoveAdsCard: View {
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
