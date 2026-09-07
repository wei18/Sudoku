// TodayAllDoneBlock — TODAY's `allDone` state (#1021 Phase A, design.md §3.1:
// "allDone: 三卡改為「今天完成了 + 明日預告」;badge 消失").
//
// `title`/`subtitle` are caller-supplied, ALREADY-localized strings rather
// than a `noun:` parameter this view interpolates itself — Sudoku and
// Minesweeper word this differently enough ("puzzles" vs "boards") that
// baking one template here would need per-language noun-agreement grammar
// this view has no business owning. Keeps this file L10n-key-free.

public import SwiftUI

public struct TodayAllDoneBlock: View {
    @Environment(\.theme) private var theme
    @ScaledSpacing(.small) private var contentGap

    private let title: String
    private let subtitle: String

    public init(title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(spacing: contentGap) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(theme.status.success.resolved)
            Text(title)
                .font(.headline)
                .foregroundStyle(theme.text.primary.resolved)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(theme.text.secondary.resolved)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}
