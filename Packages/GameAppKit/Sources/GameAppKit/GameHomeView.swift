// GameHomeView — shared Home view for all games (#557 SDD-005 C).
//
// Generalized from the three per-game HomeViews (SudokuUI.HomeView,
// MinesweeperUI.MinesweeperHomeView, Game2048UI.Game2048HomeView), all of which
// were thin wrappers over `GameShellUI.HomeScreen`.
//
// Universal capabilities (always present, every game):
//   - `HomeScreen` scaffold (mode cards from `GameHomeViewModel.modeItems`)
//   - `ResumePill` header (from `rootVM.resumeCandidate`) — #387 / #554
//   - ATT-primed `BannerSlotView` banner (from deps.adProvider/adGate/attPrimer)
//
// Per-game content (injected via GameConfig → GameHomeViewModel):
//   - navigation title (`config.title`)
//   - per-mode subtitle copy + route mapping (`config.homeModes`)
//
// The GC-signed-out `.alert` and `.attPrimerSheet` are applied by `makeGameApp`
// on the outer `GameRoot` view — NOT here. This mirrors the former `RootView`
// structure (#513 fix: alert-on-stable-VM footgun).
//
// #441: `BannerSlotView` is tinted from `\.theme` tokens (same as former
// `SudokuUI.HomeView.bannerSlot`).

public import SwiftUI
public import GameShellUI
public import MonetizationCore
public import MonetizationUI

@MainActor
public struct GameHomeView<Route: Hashable & Sendable>: View {
    private let viewModel: GameHomeViewModel<Route>
    private let rootViewModel: GameRootViewModel<Route>
    private let title: LocalizedStringKey
    private let adProvider: any AdProvider
    private let adGate: AdGate
    private let attPrimer: ATTPrimerCoordinator

    @Environment(\.theme) private var theme

    public init(
        viewModel: GameHomeViewModel<Route>,
        rootViewModel: GameRootViewModel<Route>,
        title: LocalizedStringKey,
        adProvider: any AdProvider,
        adGate: AdGate,
        attPrimer: ATTPrimerCoordinator
    ) {
        self.viewModel = viewModel
        self.rootViewModel = rootViewModel
        self.title = title
        self.adProvider = adProvider
        self.adGate = adGate
        self.attPrimer = attPrimer
    }

    public var body: some View {
        HomeScreen(
            items: viewModel.modeItems,
            header: { resumeHeader },
            secondaryLink: { statsLink },
            banner: { bannerSlot }
        )
        .navigationTitle(title)
        .background(theme.surface.background.resolved)
    }

    // MARK: - Statistics entry (#773 / #844)

    /// Home entry below the four mode cards. Hidden (`EmptyView`) when the
    /// game's `GameConfig.statsRoute` is `nil`. #844 owner override: renders
    /// with the SAME `HomeModeCard` the four modes use (was a lighter-weight
    /// `HomeSecondaryEntryLink` flat row under #773's original adjudication)
    /// — position stays the 5th entry below the grid, only the format changed.
    @ViewBuilder
    private var statsLink: some View {
        if viewModel.showsStatsEntry {
            Button {
                viewModel.selectStats()
            } label: {
                HomeModeCard(
                    symbolName: "chart.bar",
                    titleKey: "Statistics",
                    subtitleKey: viewModel.statsCardSubtitleKey
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, theme.spacing.medium)
            .padding(.bottom, theme.spacing.medium)
        }
    }

    // MARK: - ResumePill header (#387 / #554)

    /// Universal ResumePill header: renders when a resume candidate is available,
    /// scrolls with the mode cards (injected into HomeScreen's `header` slot).
    @ViewBuilder
    private var resumeHeader: some View {
        if let candidate = rootViewModel.resumeCandidate {
            ResumePill(title: candidate.title, subtitle: candidate.subtitle) {
                rootViewModel.resumeTapped()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    // MARK: - BannerSlotView (#371 / #195 / #441)

    /// ATT-primed themed banner slot. ATT priming fires at the first ad-relevant
    /// moment (gate open) via `onAdContext` — same as the former SudokuUI wiring.
    @ViewBuilder
    private var bannerSlot: some View {
        let onAdContext: (@Sendable () async -> Void)? = { [attPrimer] in
            await attPrimer.maybePresentOnAdContext()
        }
        BannerSlotView(
            adProvider: adProvider,
            adGate: adGate,
            bannerHost: adProvider as? any BannerViewProviding,
            onAdContext: onAdContext,
            // #688 item 2: was `theme.surface.placeholder.resolved` — the
            // "card" placeholder tone reads as a mismatched seam against the
            // page background below the mode-card grid (audit-ms-01, dark
            // mode). Match the page background instead so an empty/loading
            // slot is invisible; the real ad or "Ad unavailable" caption
            // still renders on top when the slot is actually showing.
            backgroundColor: theme.surface.background.resolved,
            progressTint: theme.accent.primary.resolved,
            captionColor: theme.text.secondary.resolved,
            dismissTint: theme.accent.muted.resolved.opacity(0.7)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
