// Game2048HomeView — Tiles2048 home screen.
//
// Thin wrapper over `GameShellUI.HomeScreen`. Mirrors MinesweeperHomeView.
// M4 additions vs M3:
//   - Banner slot (adProvider + adGate → BannerSlotView injection)
//   - Monetization bootstrap task
//   - ViewModel-driven navigation (replaces callback closures from M3)

public import SwiftUI
public import MonetizationCore
public import MonetizationUI
internal import GameShellUI

public struct Game2048HomeView: View {
    @Bindable private var viewModel: Game2048HomeViewModel
    private let adProvider: (any AdProvider)?
    private let adGate: AdGate?
    private let monetizationController: MonetizationStateController?
    @Environment(\.theme) private var theme

    public init(
        viewModel: Game2048HomeViewModel,
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
            cardAccessibilityIdentifier: { mode in "Game2048HomeView.\(mode.rawValue)Card" },
            banner: {
                if let adProvider, let adGate {
                    BannerSlotView(
                        adProvider: adProvider,
                        adGate: adGate,
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
        .navigationTitle("2048 Tiles")
        .task {
            if let controller = monetizationController {
                await controller.bootstrap()
            }
        }
    }
}

#Preview("Game2048Home") {
    NavigationStack {
        Game2048HomeView(viewModel: Game2048HomeViewModel())
            .environment(\.theme, Game2048Theme())
    }
}
