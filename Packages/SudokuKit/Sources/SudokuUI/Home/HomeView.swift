// HomeView — 4 mode cards (Daily / Practice / Leaderboard / Settings).
//
// Per docs/designs/02-home.md. Single state, no loading. Liquid Glass on
// each card (.glassEffect available on iOS 26 / macOS 26 — the deployment
// targets per foundations.md §1).
//
// v2.3.4: an optional `BannerSlotView` lives below the mode cards. The slot
// itself decides whether to render anything (it consults `AdGate`); HomeView
// just hands it the protocol deps. When the gate says no banner the slot
// collapses to 0pt so the layout is unaffected.

public import MonetizationCore
public import SwiftUI

public struct HomeView: View {
    @Bindable private var viewModel: HomeViewModel
    private let adProvider: (any AdProvider)?
    private let adGate: AdGate?
    @Environment(\.theme) private var theme
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(
        viewModel: HomeViewModel,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil
    ) {
        self.viewModel = viewModel
        self.adProvider = adProvider
        self.adGate = adGate
    }

    public var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(HomeMode.allCases) { mode in
                    Button {
                        viewModel.select(mode)
                    } label: {
                        ModeCard(mode: mode)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)

            if let adProvider, let adGate {
                BannerSlotView(adProvider: adProvider, adGate: adGate)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
        .background(theme.surface.background.resolved)
        .navigationTitle("Sudoku")
    }

    private var columns: [GridItem] {
        if sizeClass == .regular {
            return [GridItem(.flexible()), GridItem(.flexible())]
        }
        return [GridItem(.flexible())]
    }
}

struct ModeCard: View {
    let mode: HomeMode
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

private extension HomeMode {
    var titleKey: LocalizedStringKey {
        switch self {
        case .daily: "Daily"
        case .practice: "Practice"
        case .leaderboard: "Leaderboard"
        case .settings: "Settings"
        }
    }

    var subtitleKey: LocalizedStringKey {
        switch self {
        case .daily: "3 puzzles today"
        case .practice: "Mixed difficulty pool"
        case .leaderboard: "Global / friends"
        case .settings: "Account / language"
        }
    }

    var symbolName: String {
        switch self {
        case .daily: "calendar"
        case .practice: "dice"
        case .leaderboard: "trophy.fill"
        case .settings: "gear"
        }
    }
}
