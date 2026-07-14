// MinesweeperStatsView — Statistics screen v1 (#773).
//
// Per-app mirror of Sudoku's `StatsView` (the issue's explicit scope note:
// per-app screens, no shared cross-app Stats extraction) — read that file's
// header for the full design rationale. Summary of the shared contract:
//   - Two stacked sections (Daily, then Practice), no segmented control.
//   - One flat tile per difficulty (Beginner / Intermediate / Expert) with
//     completed count / best time / average time; `difficulty.*` token dot
//     in its established signaling-only role (Beginner→easy,
//     Intermediate→medium, Expert→hard — same mapping as the MS hubs).
//   - No win-rate tile (no loss data), no streak, no celebratory anything,
//     no monetization surface.
//   - compact: 1-column tiles; regular: 3 columns + 960pt clamp-and-center;
//     `.accessibility3+`: everything stacks vertically, nothing truncates.
//   - VoiceOver: each tile is ONE combined element with an explicit
//     localized label ("Beginner, 14 completed, best time 3 minutes
//     12 seconds, …").

internal import Foundation
public import SwiftUI
import GameShellUI
internal import MinesweeperEngine

public struct MinesweeperStatsView: View {
    private let viewModel: MinesweeperStatsViewModel

    @Environment(\.theme) private var theme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    // Section-to-section gap: content-adjacent (wraps text-bearing sections),
    // scales with Dynamic Type per the two-tier spacing contract (#762).
    @ScaledSpacing(.large) private var sectionGap
    @ScaledSpacing(.small) private var headerGap

    public init(viewModel: MinesweeperStatsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: sectionGap) {
                section(titleKey: "Daily", tiles: viewModel.dailyTiles)
                section(titleKey: "Practice", tiles: viewModel.practiceTiles)
                Text("Stats sync with your iCloud account.")
                    .font(.caption2)
                    .foregroundStyle(theme.text.tertiary.resolved)
            }
            .padding(theme.spacing.medium)
            // Proposal §3.5: 960pt clamp-and-center in the Mac detail column
            // (same treatment as the boards) — a no-op on compact widths.
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(theme.surface.background.resolved)
        .navigationTitle(Text("Statistics", bundle: .main))
        // Leaf-view one-shot bootstrap — `.task` is the idiomatic choice here
        // (#607: leaf `.task` links clean; only the app-root bootstrap is
        // restricted to `.onAppear { Task }`).
        .task { await viewModel.bootstrap() }
    }

    @ViewBuilder
    private func section(titleKey: LocalizedStringKey, tiles: [MinesweeperStatsTile]) -> some View {
        VStack(alignment: .leading, spacing: headerGap) {
            Text(titleKey)
                .font(.title2.weight(.semibold))
                .foregroundStyle(theme.text.primary.resolved)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, alignment: .leading, spacing: tileGridGap) {
                ForEach(tiles) { tile in
                    MinesweeperStatsTileView(tile: tile)
                }
            }
        }
    }

    // Tile-to-tile grid gap — structural (card outer gap, fixed per the
    // two-tier contract), same 12pt named-constant convention as
    // `HomeScreen.cardGridGap`.
    private let tileGridGap: CGFloat = 12

    private var columns: [GridItem] {
        // `.accessibility3+` forces single-column stacking BEFORE the
        // size-class check (a regular-width iPad at AX sizes must stack too).
        if dynamicTypeSize >= .accessibility3 {
            return [GridItem(.flexible())]
        }
        if sizeClass == .regular {
            return [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        }
        return [GridItem(.flexible())]
    }
}

// MARK: - MinesweeperStatsTileView

struct MinesweeperStatsTileView: View {
    let tile: MinesweeperStatsTile

    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    // Content-tier paddings/gaps (adjacent to text) — scale with Dynamic Type.
    @ScaledSpacing(.medium) private var tilePadding
    @ScaledSpacing(.small) private var innerGap

    var body: some View {
        VStack(alignment: .leading, spacing: innerGap) {
            HStack(spacing: 8) { // spacing-exempt: 8pt dot-to-name gap mirrors MinesweeperDailyHubView's card header row
                Circle()
                    .fill(difficultyTint)
                    .frame(width: 10, height: 10)
                Text(LocalizedStringKey(tile.difficulty.rawValue.capitalized))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(theme.text.primary.resolved)
            }
            statColumns
        }
        .padding(tilePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface.primary.resolved, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    /// At `.accessibility3+` the three stat columns stack vertically instead
    /// of sharing one row — no label or number may truncate (proposal §3.5).
    @ViewBuilder
    private var statColumns: some View {
        let stats: [(value: String, labelKey: LocalizedStringKey)] = [
            ("\(tile.completedCount)", "Completed"),
            (Self.timeLabel(tile.bestTimeSeconds), "Best"),
            (Self.timeLabel(tile.averageTimeSeconds), "Average")
        ]
        if dynamicTypeSize >= .accessibility3 {
            VStack(alignment: .leading, spacing: innerGap) {
                ForEach(0..<stats.count, id: \.self) { index in
                    statColumn(value: stats[index].value, labelKey: stats[index].labelKey)
                }
            }
        } else {
            HStack(alignment: .top) {
                ForEach(0..<stats.count, id: \.self) { index in
                    statColumn(value: stats[index].value, labelKey: stats[index].labelKey)
                    if index < stats.count - 1 { Spacer() }
                }
            }
        }
    }

    private func statColumn(value: String, labelKey: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) { // spacing-exempt: 2pt value-to-label gap mirrors HomeModeCard's title-to-subtitle gap
            Text(value)
                .font(.title3.weight(.medium))
                .foregroundStyle(theme.text.primary.resolved)
            Text(labelKey)
                .font(.caption)
                .foregroundStyle(theme.text.secondary.resolved)
        }
    }

    /// Beginner→easy, Intermediate→medium, Expert→hard — the same
    /// three-tier mapping the MS hubs already apply to these tokens.
    private var difficultyTint: Color {
        switch tile.difficulty {
        case .beginner: return theme.difficulty.easy.resolved
        case .intermediate: return theme.difficulty.medium.resolved
        case .expert: return theme.difficulty.hard.resolved
        }
    }

    /// `m:ss` display label; em-dash placeholder while no data exists
    /// (never-won difficulty, still-loading fetch, offline degrade).
    static func timeLabel(_ seconds: Int?) -> String {
        guard let seconds else { return "—" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// Combined VoiceOver label — mirror of Sudoku's `StatsTileView`.
    private var accessibilityDescription: String {
        let key = tile.difficulty.rawValue.capitalized
        let name = Bundle.main.localizedString(forKey: key, value: key, table: nil)
        var parts = [name, String(localized: "\(tile.completedCount) completed", bundle: .main)]
        if let best = tile.bestTimeSeconds {
            parts.append(String(localized: "best time \(Self.spokenTime(best))", bundle: .main))
        } else {
            parts.append(String(localized: "no best time yet", bundle: .main))
        }
        if let average = tile.averageTimeSeconds {
            parts.append(String(localized: "average time \(Self.spokenTime(average))", bundle: .main))
        }
        return parts.joined(separator: ", ")
    }

    static func spokenTime(_ seconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 60 ? [.minute, .second] : [.second]
        formatter.unitsStyle = .full
        return formatter.string(from: TimeInterval(seconds)) ?? "\(seconds)"
    }
}
