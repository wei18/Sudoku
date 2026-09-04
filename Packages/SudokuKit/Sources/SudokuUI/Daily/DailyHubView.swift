// DailyHubView — 3 puzzle cards per day, checkmark on completion.
//
// Per docs/designs/v3/design.md §3.1 (#1021 Phase B). `exhausted` renders as
// an inline icon+message+action block (#768) instead of a system `.alert`
// over a blank backdrop. #1021 CR2 M7: a phase-1 fetch failure (`.failed`)
// no longer gets its own overlay either — it renders the SAME
// skeleton-dimension card grid as idle/loading, captioned "Not started"
// (see `loadingCards`/`liftedState` below) — so the shell's `failure:` slot
// is unreachable here and this view no longer passes one.
//
// PR U12: chrome + responsive grid + state-switch scaffold extracted into
// `GameShellUI.DailyHubShellView`. This view now produces the
// game-specific `DailyCard` items + empty overlay + Sudoku theme
// colors and hands them to the generic shell. `.task` stays on the caller
// (matches X4 / SettingsShellView precedent: shells own no side-effect
// modifiers).
//
// #1021 Phase B: the old per-app `DailyStripView` week-strip CARD (with its
// own glass-adjacent elevated-surface chrome) is retired from the header slot
// in favor of the shared, content-layer `GameShellUI.StreakHeaderView`
// (design.md §4.2 — a streak row is plain text, not a card). `DailyPuzzleCard`
// (this file's old glass-effect card) is retired in favor of the shared
// `GameShellUI.DailyCardContent`, fed by the pure `TodayMapper`.
//
// LOADING STATE (design.md §3.1 "保留格線結構,不是空白方塊"): `DailyHubShellView`'s
// additive `loading:` slot (Leader ruling) renders 3 skeleton
// `DailyCardContent` rows in the same 1-/3-column grid the loaded state uses
// — `TodayMapper.skeletonCards()` supplies the models, `skeletonColumns`
// below calls the shared `DailyHubGridLayout.columnCount(...)` (#1021 Phase
// G) so the grid doesn't visibly reflow once real data lands.

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
    // #1021 Phase B: mirrors `DailyHubShellView`'s own (private) column-count
    // rule so the `loading:` skeleton grid doesn't visibly reflow once real
    // data replaces it.
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
            // #1021 Phase F2 (design.md §2.1/§3.1): the tab is "Today" in
            // 3.0 — reuses the existing "Today" L10n key (already localized
            // for the `AppTab` title) rather than adding a new one.
            title: "Today",
            backgroundColor: theme.surface.background.resolved,
            state: liftedState,
            card: { card in
                if let model = todayPresentation.cards.first(where: { $0.id == card.id }) {
                    DailyCardContent(model: model)
                }
            },
            // #1021 CR2 M7: no `failure:` argument — `liftedState` never
            // produces `.failed` anymore (a phase-1 fetch failure now renders
            // degraded skeleton cards via `.loading`, see below), so the
            // shell's default `Color.clear` failure overlay is correctly
            // unreachable. The old inline warning block (and its
            // `"sudoku.dailyHub.failure"` XCUITest anchor) is gone —
            // `SudokuE2ETests.test_dailyLoadFailureShowsDegradedCardsNotAlert_N5`
            // was re-pointed to assert the new degraded-cards render instead.
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
            banner: { banner },
            loading: {
                ScrollView {
                    // spacing-exempt: 12pt matches `DailyHubShellView.cardGridGap`
                    // (predates the 5-tier scale) — kept identical so the
                    // skeleton grid's geometry is byte-for-byte the real grid's.
                    LazyVGrid(columns: skeletonColumns, spacing: 12) {
                        ForEach(loadingCards) { model in
                            DailyCardContent(model: model)
                        }
                    }
                    .padding(theme.spacing.medium)
                }
            }
        )
    }

    /// #1021 CR2 M7: this slot now renders TWO distinct fixtures depending on
    /// WHY there's nothing real to show yet — blank skeleton cards for a
    /// genuine `.idle`/`.loading` fetch in flight, or `TodayMapper`'s
    /// "Not started" degraded cards once phase-1 has actually FAILED (no
    /// puzzle data will ever arrive for this session). Either way the shell
    /// state is `.loading` (see `liftedState`) — a placeholder card with no
    /// real `puzzleId` behind it must not be wrapped in the shell's per-item
    /// tappable `Button`.
    private var loadingCards: [DailyCardModel] {
        if case .failed = viewModel.state {
            return TodayMapper.degradedSkeletonCards()
        }
        return TodayMapper.skeletonCards()
    }

    private var skeletonColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible()),
            count: DailyHubGridLayout.columnCount(sizeClass: sizeClass, dynamicTypeSize: dynamicTypeSize)
        )
    }

    /// Translates Sudoku's `DailyHubState` (with `.exhausted`/`.failed`) into
    /// the generic `HubLoadState<DailyCard>` shell input. `.exhausted` maps
    /// to `.empty`, rendered inline via the `empty:` builder passed to
    /// `DailyHubShellView` above (#768). #1021 CR2 M7: `.failed` maps to
    /// `.loading` — a phase-1 fetch failure has no real `[DailyCard]` to
    /// hand the shell's per-item, tappable `.loaded` path, so it rides the
    /// same inert `loading:` slot idle/loading already use; `loadingCards`
    /// above picks the "Not started" degraded fixture over the blank one by
    /// re-checking `viewModel.state` (this shell-level type has already
    /// erased the distinction by the time `body` reads it, so this switch
    /// alone can't smuggle the degraded/blank choice through — see
    /// `loadingCards`).
    private var liftedState: HubLoadState<DailyCard> {
        switch viewModel.state {
        case .idle, .loading, .failed: return .loading
        case .loaded(let cards): return .loaded(cards)
        case .exhausted: return .empty
        }
    }
}
