// DailyHubView — 3 puzzle cards per day, checkmark on completion.
//
// Per docs/designs/03-daily-hub.md. Failure path `exhausted` surfaces as
// an Alert per docs/v1/design.md §How.6.3.
//
// PR U12: chrome + responsive grid + state-switch scaffold extracted into
// `GameShellUI.DailyHubShellView`. This view now produces the
// game-specific `DailyCard` items + failure overlay + Sudoku theme colors
// and hands them to the generic shell. `.task` and the `.exhausted`
// `.alert` stay on the caller (matches X4 / SettingsShellView precedent:
// shells own no side-effect modifiers).

public import MonetizationCore
public import SwiftUI
internal import GameShellUI
internal import SudokuEngine

public struct DailyHubView<Banner: View>: View {
    @Bindable private var viewModel: DailyHubViewModel
    @Environment(\.theme) private var theme
    private let banner: Banner

    public init(
        viewModel: DailyHubViewModel,
        @ViewBuilder banner: () -> Banner = { EmptyView() }
    ) {
        self.viewModel = viewModel
        self.banner = banner()
    }

    public var body: some View {
        DailyHubShellView(
            title: "Daily",
            backgroundColor: theme.surface.background.resolved,
            state: liftedState,
            card: { card in DailyPuzzleCard(card: card) },
            failure: { reason in
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(theme.status.warning.resolved)
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(theme.text.secondary.resolved)
                }
            },
            onItemTap: { card in viewModel.cardTapped(card) },
            banner: { banner }
        )
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

    /// Translates Sudoku's `DailyHubState` (with `.exhausted`) into the
    /// generic `HubLoadState<DailyCard>` shell input. `.exhausted` maps to
    /// `.empty` per the shell's documented semantic — the surfacing alert
    /// stays driven off `viewModel.state == .exhausted` directly so the
    /// Sudoku-specific prose is unchanged.
    private var liftedState: HubLoadState<DailyCard> {
        switch viewModel.state {
        case .idle: return .idle
        case .loading: return .loading
        case .loaded(let cards): return .loaded(cards)
        case .exhausted: return .empty
        case .failed(let reason): return .failed(reason)
        }
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
        // `.buttonStyle(.plain)` on macOS shrinks the hit area to the
        // opaque rendered content (Text + Circle + MiniBoardStrip), so
        // taps on the padding / glass-effect surround silently miss.
        // `.contentShape(Rectangle())` makes the entire card frame
        // tap-hittable. Must come BEFORE `.glassEffect(...)` so the glass
        // material's own hit-test doesn't override us — mirrors HomeView's
        // working ModeCard / RemoveAdsCard ordering (issue #15 / #197).
        .contentShape(Rectangle())
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
