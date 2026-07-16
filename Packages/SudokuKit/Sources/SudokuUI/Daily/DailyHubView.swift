// DailyHubView — 3 puzzle cards per day, checkmark on completion.
//
// Per docs/designs/03-daily-hub.md. Failure path `exhausted` renders as an
// inline icon+message+action block (#768) — matches the `.failed` visual
// language instead of a system `.alert` over a blank backdrop.
//
// PR U12: chrome + responsive grid + state-switch scaffold extracted into
// `GameShellUI.DailyHubShellView`. This view now produces the
// game-specific `DailyCard` items + failure/empty overlays + Sudoku theme
// colors and hands them to the generic shell. `.task` stays on the caller
// (matches X4 / SettingsShellView precedent: shells own no side-effect
// modifiers).

public import MonetizationCore
public import SwiftUI
internal import GameAppKit
internal import GameShellUI
internal import SudokuEngine

public struct DailyHubView<Banner: View>: View {
    // #536: @State (first-value-wins) so a re-render that mints a fresh idle
    // VM from the factory does not replace the bootstrapped instance. The view
    // keeps the same SwiftUI identity across re-renders, so @State retains the
    // first VM. @Bindable was a plain assignment — a re-render would swap it out
    // and leave the hub stuck at .idle (banner WebView re-render trigger).
    @State private var viewModel: DailyHubViewModel
    @Environment(\.theme) private var theme
    // #761: `.onAppear` does NOT re-fire when the board's fullScreenCover
    // dismisses (sim-verified — no re-fire on the real Close → Leave flow;
    // the only re-fire is a transient GameBoardRedirect push-pop at board
    // OPEN, which is useless here since completion doesn't exist yet). This
    // hub instead listens to `GameRoot`'s explicit teardown counter, mirroring
    // the `ResumePill` / `refreshResumeCandidate` precedent (#675).
    @Environment(\.gameSessionTeardownCount) private var sessionTeardownCount
    private let banner: Banner
    // Exhausted-state card padding (#762 PR2 two-tier spacing contract) —
    // content tier, wraps the icon/message/action-button stack, scales
    // with Dynamic Type.
    @ScaledSpacing(.large) private var exhaustedCardPadding

    public init(
        viewModel: DailyHubViewModel,
        @ViewBuilder banner: () -> Banner = { EmptyView() }
    ) {
        _viewModel = State(wrappedValue: viewModel)
        self.banner = banner()
    }

    public var body: some View {
        // #774: the week strip sits above the trio, outside
        // `DailyHubShellView` (GameShellKit stays untouched — see
        // `DailyStripView`'s header comment on the "no shared widget"
        // scope note). It renders regardless of the shell's own
        // idle/loading/loaded/failed state — the strip has its own
        // independent fetch and shouldn't disappear just because the
        // trio failed to generate.
        VStack(spacing: 0) {
            DailyStripView(snapshot: viewModel.weekStrip, onDayTap: { day in viewModel.dayTapped(day) })
                .padding(.horizontal, theme.spacing.medium)
                .padding(.top, theme.spacing.medium)
            dailyHubShell
        }
        .background(theme.surface.background.resolved)
        .task { await viewModel.bootstrap() }
        // #761: driven by `GameRoot`'s explicit teardown counter (not
        // `.onAppear` — see the property doc above for why that doesn't
        // work). `refresh()`'s own `.loaded`-state guard still protects
        // against a spurious fetch before `bootstrap()` has landed. Also
        // refreshes `viewModel.weekStrip` (#774) — same `refresh()` call,
        // no new trigger.
        .onChange(of: sessionTeardownCount) { _, _ in Task { await viewModel.refresh() } }
        // #826: a past day with >1 completed difficulty presents this picker
        // instead of opening directly (owner adjudication 2026-07-16).
        // `presenting:` hands the whole array to `actions:` so `ForEach` can
        // build one row per completed difficulty.
        .confirmationDialog(
            "Difficulty",
            isPresented: Binding(
                get: { viewModel.reviewPickerChoices != nil },
                set: { isPresented in
                    if !isPresented { viewModel.dismissReviewPicker() }
                }
            ),
            presenting: viewModel.reviewPickerChoices
        ) { choices in
            ForEach(choices) { choice in
                Button(LocalizedStringKey(choice.difficulty.rawValue.capitalized)) {
                    viewModel.reviewChoiceSelected(choice)
                }
            }
        }
    }

    private var dailyHubShell: some View {
        DailyHubShellView(
            title: "Daily",
            backgroundColor: theme.surface.background.resolved,
            state: liftedState,
            card: { card in DailyPuzzleCard(card: card) },
            failure: { reason in
                // spacing-exempt: 12pt predates the 5-tier `SpacingTokens`
                // scale — no matching tier without snapping and changing
                // this block's existing layout/snapshot (#762 PR2).
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(theme.status.warning.resolved)
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(theme.text.secondary.resolved)
                }
            },
            // #768: `.exhausted` renders inline instead of a system `.alert`
            // over a blank backdrop — same icon+message language as
            // `failure` above, plus the #686 action pair as inline buttons.
            // Text reuses the exact strings the alert used to show (no new
            // L10n keys). Both actions are wired unchanged from #686.
            empty: {
                // spacing-exempt: 12pt predates the 5-tier `SpacingTokens`
                // scale — same rationale as `failure` above (#762 PR2).
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(theme.status.warning.resolved)
                        .accessibilityHidden(true)
                    Text("Couldn't generate today's puzzle")
                        .foregroundStyle(theme.text.primary.resolved)
                    Text("Try a different difficulty, or come back tomorrow.")
                        .font(.caption)
                        .foregroundStyle(theme.text.secondary.resolved)
                        .multilineTextAlignment(.center)
                    // spacing-exempt: 12pt predates the 5-tier
                    // `SpacingTokens` scale — same rationale as above (#762 PR2).
                    HStack(spacing: 12) {
                        // #686: the label promised a difficulty picker this
                        // hub doesn't have — route to the Practice hub that
                        // actually has one (reuses the existing "Practice"
                        // key, same string the Home card/PracticeHubView
                        // title already surface).
                        Button {
                            viewModel.tryPracticeInstead()
                        } label: {
                            Text("Practice")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        // Pops back to Home rather than leaving the user on
                        // the `.exhausted` hub's blank backdrop with no
                        // recovery — same navigation #686 wired into the
                        // alert's Cancel button.
                        Button {
                            viewModel.dismissExhausted()
                        } label: {
                            Text("Cancel")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
                .padding(exhaustedCardPadding)
            },
            onItemTap: { card in viewModel.cardTapped(card) },
            banner: { banner }
        )
    }

    /// Translates Sudoku's `DailyHubState` (with `.exhausted`) into the
    /// generic `HubLoadState<DailyCard>` shell input. `.exhausted` maps to
    /// `.empty`, rendered inline via the `empty:` builder passed to
    /// `DailyHubShellView` above (#768).
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
    // Card content rhythm (#762 PR2 two-tier spacing contract) — content
    // tier, wraps the difficulty/checkmark row + mini board strip, scales
    // with Dynamic Type.
    @ScaledSpacing(.small) private var cardContentGap
    // Card internal padding (#762 PR2 two-tier spacing contract) — content
    // tier, scales with Dynamic Type.
    @ScaledSpacing(.medium) private var cardPadding

    var body: some View {
        VStack(alignment: .leading, spacing: cardContentGap) {
            HStack(spacing: cardContentGap) {
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
                    // #516: a "tap to play" chevron reads clearer than the bare
                    // em-dash, which looked like a placeholder rather than an
                    // unplayed state. Decorative — the card's combined a11y
                    // element already conveys the difficulty + button trait.
                    Image(systemName: "chevron.right")
                        .font(.callout)
                        .foregroundStyle(theme.text.tertiary.resolved)
                        .accessibilityHidden(true)
                }
            }
            MiniBoardStrip()
                .accessibilityHidden(true)
        }
        .padding(cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        // `.buttonStyle(.plain)` on macOS shrinks the hit area to the
        // opaque rendered content (Text + Circle + MiniBoardStrip), so
        // taps on the padding / glass-effect surround silently miss.
        // `.contentShape(Rectangle())` makes the entire card frame
        // tap-hittable. Must come BEFORE `.glassEffect(...)` so the glass
        // material's own hit-test doesn't override us — mirrors HomeView's
        // working ModeCard ordering (issue #15 / #197; the RemoveAds card itself
        // left Home in SDD-003 Epic 7).
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
        // spacing-exempt: 3pt decorative mini-grid gap — a cosmetic
        // strip of 9 tiles, not adjacent to real text/icon content and not
        // part of the 5-tier `SpacingTokens` scale. Flagged for owner
        // review rather than silently snapped (#762 PR2).
        HStack(spacing: 3) {
            ForEach(0..<9, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.text.tertiary.resolved.opacity(index.isMultiple(of: 2) ? 0.18 : 0.08))
                    .frame(height: 8)
            }
        }
    }
}
