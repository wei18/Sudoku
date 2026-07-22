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
        // #840: the week strip is injected into `DailyHubShellView`'s
        // `header` slot (GameShellKit stays untouched — see
        // `DailyStripView`'s header comment on the "no shared widget"
        // scope note) instead of sitting as a fixed sibling above the
        // shell (#774's original placement, which made the trio scroll
        // UNDER a pinned strip — owner-reported regression). The shell
        // renders `header` in every state — idle/loading/loaded/empty/
        // failed — so the strip still can't disappear just because the
        // trio failed to generate, and in `.loaded` it now scrolls WITH
        // the card grid.
        dailyHubShell
            .task { await viewModel.bootstrap() }
            // #761: driven by `GameRoot`'s explicit teardown counter (not
            // `.onAppear` — see the property doc above for why that doesn't
            // work). `refresh()`'s own `.loaded`-state guard still protects
            // against a spurious fetch before `bootstrap()` has landed. Also
            // refreshes `viewModel.weekStrip` (#774) — same `refresh()` call,
            // no new trigger.
            .onChange(of: sessionTeardownCount) { _, _ in Task { await viewModel.refresh() } }
            // #826: a past day with >1 completed difficulty presents this
            // picker instead of opening directly (owner adjudication
            // 2026-07-16). `presenting:` hands the whole array to `actions:`
            // so `ForEach` can build one row per completed difficulty.
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
                // #935 N5: stable, non-localized anchor for the inline
                // fetch-failure surface (host-driven XCUITest E2E — see
                // `DailyHubViewModel.bootstrap()`'s non-exhausted catch branch).
                .accessibilityIdentifier("sudoku.dailyHub.failure")
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
                        // #935 N4: stable, non-localized anchor for the
                        // exhausted-block message (host-driven XCUITest E2E —
                        // see `DailyHubViewModel.bootstrap()`'s
                        // `.generatorFailed` branch). Deliberately placed on
                        // this leaf `Text`, not the enclosing `VStack` — an
                        // identifier set on a container cascades down and
                        // clobbers its accessibility-element descendants'
                        // OWN identifiers (verified: the Practice/Cancel
                        // buttons below both reported the container's id
                        // instead of their own until this was moved off the
                        // VStack).
                        .accessibilityIdentifier("sudoku.dailyHub.exhausted")
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
                        .tint(theme.accent.primary.resolved)
                        .controlSize(.large)
                        // #935 N4: stable, non-localized anchor for the
                        // exhausted block's "Practice" CTA (host-driven
                        // XCUITest E2E).
                        .accessibilityIdentifier("sudoku.dailyHub.exhausted.practice")
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
                        // #935 N4: stable, non-localized anchor for the
                        // exhausted block's "Cancel" CTA (host-driven
                        // XCUITest E2E).
                        .accessibilityIdentifier("sudoku.dailyHub.exhausted.cancel")
                    }
                }
                .padding(exhaustedCardPadding)
            },
            onItemTap: { card in viewModel.cardTapped(card) },
            header: {
                DailyStripView(snapshot: viewModel.weekStrip, onDayTap: { day in viewModel.dayTapped(day) })
                    .padding(.horizontal, theme.spacing.medium)
                    .padding(.top, theme.spacing.medium)
                    // #935 batch 3: stable, loaded-hub root anchor (host-driven
                    // XCUITest E2E, N12) — a ZERO-SIZE marker composed via
                    // `.background` (a SIBLING layer, not an ancestor of
                    // `DailyStripView`'s own day-dot elements) so it cannot
                    // cascade an id onto them (#937's "container id clobbers
                    // descendant ids" lesson — see the `empty:` builder below).
                    .background(alignment: .topLeading) {
                        Color.clear
                            .frame(width: 1, height: 1)
                            .accessibilityIdentifier("sudoku.dailyHub.root")
                    }
            },
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
    // tier, wraps the difficulty/checkmark row + best-time caption, scales
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
                } else {
                    // #516: a "tap to play" chevron reads clearer than the bare
                    // em-dash, which looked like a placeholder rather than an
                    // unplayed state. Decorative — the card's explicit a11y
                    // label already conveys the difficulty + button trait.
                    Image(systemName: "chevron.right")
                        .font(.callout)
                        .foregroundStyle(theme.text.tertiary.resolved)
                }
            }
            // #886 (2026-07-19 owner adjudication, citing #875 D3): this
            // second line and MS's board-spec caption used to diverge
            // (Sudoku: decorative `MiniBoardStrip`, zero data binding; MS:
            // real "16 × 16 · 40 mines" text) — now unified to the same
            // real per-difficulty stat on both cards, replacing MS's board
            // spec too (see `MinesweeperDailyHubView.swift`'s matching note).
            Text("Best \(StatsTileView.timeLabel(card.bestTimeSeconds))")
                .font(.caption)
                .foregroundStyle(theme.text.secondary.resolved)
        }
        .padding(cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        // `.buttonStyle(.plain)` on macOS shrinks the hit area to the
        // opaque rendered content (Text + Circle + Best-time caption), so
        // taps on the padding / glass-effect surround silently miss.
        // `.contentShape(Rectangle())` makes the entire card frame
        // tap-hittable. Must come BEFORE `.glassEffect(...)` so the glass
        // material's own hit-test doesn't override us — mirrors HomeView's
        // working ModeCard ordering (issue #15 / #197; the RemoveAds card itself
        // left Home in SDD-003 Epic 7).
        .contentShape(Rectangle())
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        // #886: switched from `.combine` to an explicit composed label
        // (mirrors `StatsTileView`'s identical "dot + difficulty name +
        // stat" shape) — `.combine`'s implicit child concatenation is why
        // the best-time line was never announced before; the checkmark's own
        // `.accessibilityLabel("Completed")` moved into `accessibilityDescription`
        // below instead of being combine-concatenated.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        // #935 batch 3: stable, non-localized anchor for a COMPLETED card
        // (host-driven XCUITest E2E, N12 re-view route) — applied on the same
        // element as the combined label above, not a wrapping container, so
        // it can't cascade onto anything (this element has no accessibility
        // descendants of its own — `.accessibilityElement(children: .ignore)`).
        // Un-completed cards get no identifier (unneeded, keeps the id
        // meaningful).
        .accessibilityIdentifier(card.isCompleted ? "sudoku.dailyHub.card.completed" : "")
        // #941 (reverses #878): the card is optimistically tappable the
        // whole time now — `.isButton` no longer conditions on phase-2
        // pending state.
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

    private var accessibilityDescription: String {
        Self.accessibilityDescription(
            difficulty: card.difficulty,
            isCompleted: card.isCompleted,
            bestTimeSeconds: card.bestTimeSeconds
        )
    }

    /// #886: combined VoiceOver label — "Easy, Completed, best time 3
    /// minutes 12 seconds" / "Hard, best time 5 minutes 3 seconds" / "Medium,
    /// no best time yet". Mirrors `StatsTileView.accessibilityDescription`
    /// exactly, including reusing its existing "best time %@" / "no best
    /// time yet" keys — no new a11y keys. The completed clause is OMITTED
    /// (not a new "not completed" key) when `isCompleted` is false, matching
    /// today's actual behavior (the chevron contributed nothing to VoiceOver
    /// either). A `static func` (not a `private var`), mirroring
    /// `StatsTileView.timeLabel`/`spokenTime`, so tests can pin the composed
    /// string directly without standing up a `View`'s `@Environment` context.
    static func accessibilityDescription(difficulty: Difficulty, isCompleted: Bool, bestTimeSeconds: Int?) -> String {
        let key = difficulty.rawValue.capitalized
        let name = Bundle.main.localizedString(forKey: key, value: key, table: nil)
        var parts = [name]
        if isCompleted {
            parts.append(String(localized: "Completed", bundle: .main))
        }
        if let best = bestTimeSeconds {
            parts.append(String(localized: "best time \(StatsTileView.spokenTime(best))", bundle: .main))
        } else {
            parts.append(String(localized: "no best time yet", bundle: .main))
        }
        return parts.joined(separator: ", ")
    }
}
