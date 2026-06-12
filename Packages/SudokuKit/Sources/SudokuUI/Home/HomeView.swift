// HomeView — Sudoku's 4 mode cards (Daily / Practice / Leaderboard / Settings).
//
// Thin wrapper over `GameShellUI.HomeScreen` (#410). The shared scaffold owns
// the `ScrollView { header ; LazyVGrid(cards) ; banner }` body, the column
// sizeClass logic, the mode card rendering, and the themed background.
// HomeView keeps only the Sudoku-specific bits:
//   - the per-mode subtitles + tap routing (via `HomeViewModel.modeItems`),
//   - the banner slot (`BannerSlotView` — AdProvider / AdGate live here),
//   - the navigation title + the monetization bootstrap `.task`.
//
// #387: an optional `header` slot renders as the first child INSIDE the scroll
// region (RootView passes its ResumePill here so the pill scrolls with the mode
// cards). RootView still owns the resume-candidate state + tap closure.
//
// SDD-003 Epic 7: "Remove Ads" home card removed; Settings Purchases entry preserved.

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

