// HomeView — 4 mode cards (Daily / Practice / Leaderboard / Settings).
//
// Per docs/designs/02-home.md. Single state, no loading. Liquid Glass on
// each card (.glassEffect available on iOS 26 / macOS 26 — the deployment
// targets per foundations.md §1).

public import SwiftUI

public struct HomeView: View {
    @Bindable private var viewModel: HomeViewModel
    @Environment(\.theme) private var theme
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
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
