// MinesweeperHomeView — mode-card entry surface (#288 / #289, 2026-06-04).
//
// Mirror of `SudokuUI.HomeView`. A `LazyVGrid` of mode cards — New Game,
// Daily, Practice, Leaderboard, Settings — plus an optional 5th "Remove Ads"
// card and a `MinesweeperBannerSlotView` below, identical wiring to Sudoku's
// HomeView. Cards drive navigation through the injected `path` via
// `MinesweeperHomeViewModel.select(...)`.
//
// Styling uses `MinesweeperTheme` tokens read from `@Environment(\.theme)`
// (#278 / #296) — no hardcoded colors. The grid is single-column on compact
// width and two-column on regular (Mac / iPad), matching Sudoku.
//
// Leaderboard (#291): the card is enabled and presents Apple's native Game
// Center dashboard modally (`MinesweeperGameCenterDashboard.present`) — a side
// effect, never a route (mirrors Sudoku #49).

public import SwiftUI
public import MonetizationCore
public import MonetizationUI

public struct MinesweeperHomeView: View {
    @Bindable private var viewModel: MinesweeperHomeViewModel
    private let adProvider: (any AdProvider)?
    private let adGate: AdGate?
    private let monetizationController: MonetizationStateController?
    @Environment(\.theme) private var theme
    @Environment(\.horizontalSizeClass) private var sizeClass

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
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(MinesweeperHomeMode.allCases) { mode in
                    Button {
                        viewModel.select(mode)
                    } label: {
                        MinesweeperModeCard(mode: mode)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("MinesweeperHomeView.\(mode.rawValue)Card")
                }

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
            }
            .padding(16)

            if let adProvider, let adGate {
                MinesweeperBannerSlotView(adProvider: adProvider, adGate: adGate)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
        .background(theme.surface.background.resolved)
        .navigationTitle("Minesweeper")
        .task {
            if let controller = monetizationController {
                await controller.bootstrap()
            }
        }
    }

    private var columns: [GridItem] {
        if sizeClass == .regular {
            return [GridItem(.flexible()), GridItem(.flexible())]
        }
        return [GridItem(.flexible())]
    }
}

struct MinesweeperModeCard: View {
    let mode: MinesweeperHomeMode
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: mode.symbolName)
                .font(.title2)
                .foregroundStyle(theme.accent.primary.resolved)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.titleKey)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(theme.text.primary.resolved)
                Text(mode.subtitleKey)
                    .font(.caption)
                    .foregroundStyle(theme.text.secondary.resolved)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(theme.text.tertiary.resolved)
        }
        .padding(16)
        .frame(minHeight: 72)
        .contentShape(Rectangle())
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// 5th mode-card slot for Remove Ads. Mirrors `SudokuUI.RemoveAdsCard`:
/// tinted with `difficulty.medium` to signal commerce intent (not a difficulty
/// cue). Layout matches `MinesweeperModeCard` so the grid row height stays
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

private extension MinesweeperHomeMode {
    var titleKey: LocalizedStringKey {
        switch self {
        case .newGame: "New Game"
        case .daily: "Daily"
        case .practice: "Practice"
        case .leaderboard: "Leaderboard"
        case .settings: "Settings"
        }
    }

    var subtitleKey: LocalizedStringKey {
        switch self {
        case .newGame: "Pick a difficulty"
        case .daily: "3 boards today"
        case .practice: "All difficulties"
        case .leaderboard: "Best times"
        case .settings: "Purchases / about"
        }
    }

    var symbolName: String {
        switch self {
        case .newGame: "plus.circle"
        case .daily: "calendar"
        case .practice: "dice"
        case .leaderboard: "trophy.fill"
        case .settings: "gear"
        }
    }
}

#Preview("MinesweeperHome") {
    NavigationStack {
        MinesweeperHomeView(viewModel: MinesweeperHomeViewModel())
            .environment(\.theme, MinesweeperTheme())
    }
}
