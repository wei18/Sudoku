// DailyHubView — 3 puzzle cards per day, checkmark on completion.
//
// Per docs/designs/v3/design.md §3.1 (#1021 Phase B). Failure path
// `exhausted` renders as an inline icon+message+action block (#768) — matches
// the `.failed` visual language instead of a system `.alert` over a blank
// backdrop.
//
// PR U12: chrome + responsive grid + state-switch scaffold extracted into
// `GameShellUI.DailyHubShellView`. This view now produces the
// game-specific `DailyCard` items + failure/empty overlays + Sudoku theme
// colors and hands them to the generic shell. `.task` stays on the caller
// (matches X4 / SettingsShellView precedent: shells own no side-effect
// modifiers).
//
// #1021 Phase B: the old per-app `DailyStripView` week-strip CARD (with its
// own glass-adjacent elevated-surface chrome) is retired from the header slot
// in favor of the shared, content-layer `GameShellUI.StreakHeaderView`
// (design.md §4.2 — a streak row is plain text, not a card). `DailyPuzzleCard`
// (this file's old glass-effect card) is retired in favor of the shared
// `GameShellUI.DailyCardContent`, fed by the pure `TodayMapper`. `DailyStripView`
// ITSELF stays in the package (unused by this view now) because
// `DailyHubViewModelDayTapTests.swift` still instantiates it directly to pin
// `isTappable` — see that file, and the Phase B report's deviations section.
//
// KNOWN LOADING-STATE DEVIATION: design.md §3.1's `loading` row asks for
// skeleton CARDS (grid-preserving thumbnails) during the initial fetch, not
// just a spinner. `DailyHubShellView`'s `.idle`/`.loading` branch renders a
// bare `ProgressView` (the header — hence the streak — still renders per its
// own "every state" contract); switching that branch to a skeleton card grid
// would require widening `DailyHubShellView`'s generic `Item` shape to carry
// presentation data it doesn't otherwise need. Deferred — see the Phase B
// report.

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
    @ScaledSpacing(.medium) private var headerGap

    public init(
        viewModel: DailyHubViewModel,
        @ViewBuilder banner: () -> Banner = { EmptyView() }
    ) {
        _viewModel = State(wrappedValue: viewModel)
        self.banner = banner()
    }

    public var body: some View {
        // #1021 Phase B: the week strip / trio cards below are now built via
        // `TodayMapper` from `viewModel`'s existing published state — no new
        // reads. The shell's `header` slot still renders in every state
        // (idle/loading/loaded/empty/failed), so the streak line can never
        // disappear just because the trio failed to generate (#774's
        // original guarantee, preserved).
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

    /// #1021 Phase B: the pure state → presentation mapping, recomputed every
    /// render from `viewModel`'s already-published, already-fetched state —
    /// see `TodayMapper`'s file header.
    private var todayPresentation: TodayPresentation<DailyCardModel> {
        TodayMapper.present(
            state: viewModel.state,
            inProgress: viewModel.inProgressSummary,
            isPhase2Degraded: viewModel.isPhase2Degraded
        )
    }

    private var headerModel: StreakHeaderModel {
        TodayMapper.headerModel(
            weekStrip: viewModel.weekStrip,
            allCompletedDays: viewModel.allCompletedDays,
            today: DayKey(Date(), calendar: .current)
        )
    }

    private var dailyHubShell: some View {
        DailyHubShellView(
            title: "Daily",
            backgroundColor: theme.surface.background.resolved,
            state: liftedState,
            card: { card in
                if let model = todayPresentation.cards.first(where: { $0.id == card.id }) {
                    DailyCardContent(model: model)
                }
            },
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
            // #1021 Phase B (design.md §3.1): now wrapped in a `HubCard`
            // (standard material, no glass) instead of a bare backdrop.
            empty: {
                HubCard {
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
                            // hub doesn't have — route to the Practice tab that
                            // actually has one (reuses the existing "Practice"
                            // key, same string the Progress/PracticeHubView
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
                            // Closes the block by dropping to an empty
                            // `.loaded` state and stays on Today (#1020: Today
                            // is a tab root now, not a route to pop from).
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
                }
            },
            onItemTap: { card in viewModel.cardTapped(card) },
            header: {
                // spacing-exempt: the streak header + optional all-done block
                // gap uses the same tier as the header's own horizontal/top
                // insets below — not a new spacing decision.
                VStack(alignment: .leading, spacing: headerGap) {
                    StreakHeaderView(
                        model: headerModel,
                        onPipTap: { index in
                            guard viewModel.weekStrip.days.indices.contains(index) else { return }
                            viewModel.dayTapped(viewModel.weekStrip.days[index])
                        }
                    )
                    if case .allDone = todayPresentation {
                        TodayAllDoneBlock(
                            title: String(localized: "All done for today", bundle: .main),
                            subtitle: String(localized: "Come back tomorrow for 3 new puzzles.", bundle: .main)
                        )
                    }
                }
                .padding(.horizontal, theme.spacing.medium)
                .padding(.top, theme.spacing.medium)
                // #935 batch 3: stable, loaded-hub root anchor (host-driven
                // XCUITest E2E, N12) — a ZERO-SIZE marker composed via
                // `.background` (a SIBLING layer, not an ancestor of
                // `StreakHeaderView`'s own pip elements) so it cannot
                // cascade an id onto them (#937's "container id clobbers
                // descendant ids" lesson).
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
