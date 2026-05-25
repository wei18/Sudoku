// DailyHubView — 3 puzzle cards per day, checkmark on completion.
//
// Per docs/designs/03-daily-hub.md. Failure path `exhausted` surfaces as
// an Alert per docs/v1/design.md §How.6.3.

public import SwiftUI
internal import SudokuEngine

public struct DailyHubView: View {
    @Bindable private var viewModel: DailyHubViewModel
    @Environment(\.theme) private var theme
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(viewModel: DailyHubViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.surface.background.resolved)
            .navigationTitle("Daily")
            .task { await viewModel.bootstrap() }
            .alert(
                "Couldn't generate today's puzzle",
                isPresented: Binding(
                    get: { viewModel.state == .exhausted },
                    set: { _ in }
                ),
                actions: {
                    Button("Try another difficulty", role: .cancel) {}
                },
                message: {
                    Text("Try a different difficulty, or come back tomorrow.")
                }
            )
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView().controlSize(.large)
        case .loaded(let cards):
            cardList(cards)
        case .exhausted:
            // Alert handles the surfacing; show empty grid behind it.
            Color.clear
        case .failed(let reason):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(theme.status.warning.resolved)
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(theme.text.secondary.resolved)
            }
        }
    }

    @ViewBuilder
    private func cardList(_ cards: [DailyCard]) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(cards) { card in
                    Button {
                        viewModel.cardTapped(card)
                    } label: {
                        DailyPuzzleCard(card: card)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }

    private var columns: [GridItem] {
        if sizeClass == .regular {
            return [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ]
        }
        return [GridItem(.flexible())]
    }
}

struct DailyPuzzleCard: View {
    let card: DailyCard
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(difficultyTint)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(LocalizedStringKey(card.difficulty.rawValue.capitalized))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(difficultyTint)
                Spacer()
                if card.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.status.success.resolved)
                        .font(.callout)
                        .accessibilityLabel("Completed")
                } else {
                    Text("—")
                        .font(.callout)
                        .foregroundStyle(theme.text.tertiary.resolved)
                }
            }
            MiniBoardStrip()
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// Map the typed `Difficulty` enum to the matching `difficulty.*`
    /// theme token. M5 (issue #65): switch is exhaustive — adding a new
    /// difficulty case forces this map to update.
    private var difficultyTint: Color {
        switch card.difficulty {
        case .easy: return theme.difficulty.easy.resolved
        case .medium: return theme.difficulty.medium.resolved
        case .hard: return theme.difficulty.hard.resolved
        }
    }
}

struct MiniBoardStrip: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<9, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.text.tertiary.resolved.opacity(index.isMultiple(of: 2) ? 0.18 : 0.08))
                    .frame(height: 8)
            }
        }
    }
}
