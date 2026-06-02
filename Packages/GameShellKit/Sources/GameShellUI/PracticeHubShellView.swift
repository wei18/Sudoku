// PracticeHubShellView — generic Practice hub chrome + difficulty/CTA slots.
//
// Owns the parts of a "pick a difficulty, draw a puzzle" hub that don't
// change across games:
//   - the outer `VStack(alignment: .leading, spacing: 24)` with
//     `.padding(16)` + `.frame(maxWidth/Height: .infinity, alignment: .top)`
//   - the chrome triple (`.background(Color)` + `.navigationTitle`)
//   - the inline section header `Text` for the filter slot, with caller-
//     supplied foreground color (`headerForeground`)
//
// Caller supplies:
//   - `title` and `filterHeader` (both `LocalizedStringKey`)
//   - resolved theme colors as init params: `backgroundColor` for the chrome
//     background, `headerForeground` for the section header
//   - the `filter` slot (the game's segmented Picker, including its tint /
//     glassEffect / padding decoration — none of which the shell touches)
//   - the `cta` slot (the game's draw/start affordance — Sudoku's `drawCard`
//     with its shimmer + glassEffect, or Minesweeper's simpler Start button)
//
// Loading state (Sudoku's `PracticeHubLoadingState`) deliberately stays in
// the caller's CTA — the shell carries no state machine. Lets Minesweeper
// opt out cleanly (no async generator, no shimmer threshold today).

public import SwiftUI

public struct PracticeHubShellView<Filter, CTA>: View
where Filter: View, CTA: View {
    private let title: LocalizedStringKey
    private let backgroundColor: Color
    private let filterHeader: LocalizedStringKey
    private let headerForeground: Color
    private let filter: () -> Filter
    private let cta: () -> CTA

    public init(
        title: LocalizedStringKey,
        backgroundColor: Color,
        filterHeader: LocalizedStringKey,
        headerForeground: Color,
        @ViewBuilder filter: @escaping () -> Filter,
        @ViewBuilder cta: @escaping () -> CTA
    ) {
        self.title = title
        self.backgroundColor = backgroundColor
        self.filterHeader = filterHeader
        self.headerForeground = headerForeground
        self.filter = filter
        self.cta = cta
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(filterHeader)
                .font(.title3.weight(.semibold))
                .foregroundStyle(headerForeground)

            filter()

            cta()

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(backgroundColor)
        .navigationTitle(title)
    }
}
