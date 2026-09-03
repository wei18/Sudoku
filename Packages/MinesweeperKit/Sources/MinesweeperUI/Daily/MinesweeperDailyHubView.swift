// MinesweeperDailyHubView — date-seeded Daily hub (#290).
//
// Per docs/designs/v3/design.md §3.1 (#1021 Phase B). Mirrors Sudoku's
// `DailyHubView`: produces the game-specific `MinesweeperDailyCard` items via
// `MinesweeperTodayMapper` and hands them to the generic
// `GameShellUI.DailyHubShellView`. `.task { bootstrap() }` stays on the
// caller (shells own no side-effect modifiers — X4 / SettingsShellView
// precedent).
//
// The daily trio = one date-seeded board per difficulty (beginner /
// intermediate / expert), the same three boards for everyone on a given UTC
// day, rolling over at UTC midnight. Tapping a card pushes `.board(...)` with
// the daily seed. Completed cards show a checkmark (driven off
// `PersistenceProtocol.fetchCompletedDailyIds`; parity-only until MS daily
// save-flow lands).
//
// #1021 Phase B: the old per-app `MinesweeperDailyStripView` week-strip CARD
// is retired from the header slot in favor of the shared, content-layer
// `GameShellUI.StreakHeaderView` (design.md §4.2). `MinesweeperDailyCardView`
// (this file's old glass-effect card) is retired in favor of the shared
// `GameShellUI.DailyCardContent`, fed by `MinesweeperTodayMapper`.
//
// LOADING STATE (design.md §3.1 "保留格線結構,不是空白方塊"): `DailyHubShellView`'s
// additive `loading:` slot (Leader ruling) renders 3 skeleton
// `DailyCardContent` rows, one per daily difficulty (`MinesweeperTodayMapper.
// skeletonCards()` carries each difficulty's real board dims), in the same
// 1-/3-column grid the loaded state uses.

public import SwiftUI
internal import GameAppKit
internal import GameShellUI
internal import MinesweeperEngine

public struct MinesweeperDailyHubView<Banner: View>: View {
    // #536: @State (first-value-wins) so a re-render that mints a fresh idle
    // VM from the factory does not replace the bootstrapped instance. Mirrors
    // the Sudoku fix in DailyHubView — both share the same @Bindable bug class.
    @State private var viewModel: MinesweeperDailyHubViewModel
    @Environment(\.theme) private var theme
    // #761: `.onAppear` does NOT re-fire when the board's fullScreenCover
    // dismisses (sim-verified — no re-fire on the real Close → Leave flow;
    // the only re-fire is a transient GameBoardRedirect push-pop at board
    // OPEN, which is useless here since completion doesn't exist yet). This
    // hub instead listens to `GameRoot`'s explicit teardown counter, mirroring
    // the `ResumePill` / `refreshResumeCandidate` precedent (#675). Mirrors
    // Sudoku's `DailyHubView`.
    @Environment(\.gameSessionTeardownCount) private var sessionTeardownCount
    private let banner: Banner
    @ScaledSpacing(.medium) private var headerGap
    // #1021 Phase G: calls the shared `DailyHubGridLayout.columnCount(...)`
    // so the `loading:` skeleton grid doesn't visibly reflow once real data
    // replaces it, and follows the same AX-size single-column rule.
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        viewModel: MinesweeperDailyHubViewModel,
        @ViewBuilder banner: () -> Banner = { EmptyView() }
    ) {
        _viewModel = State(wrappedValue: viewModel)
        self.banner = banner()
    }

    public var body: some View {
        // #840: the week strip is injected into `DailyHubShellView`'s
        // `header` slot (GameShellKit stays untouched) instead of sitting as
        // a fixed sibling above the shell. The shell renders `header` in
        // every load state, so it still can't disappear. Mirrors Sudoku's
        // `DailyHubView`.
        dailyHubShell
            .task { await viewModel.bootstrap() }
            // #761: driven by `GameRoot`'s explicit teardown counter (not
            // `.onAppear` — see the property doc above for why that doesn't
            // work). `refresh()`'s own `.loaded`-state guard still protects
            // against a spurious fetch before `bootstrap()` has landed. Also
            // refreshes `viewModel.weekStrip` (#774) — same `refresh()` call,
            // no new trigger. Mirrors Sudoku's `DailyHubView`.
            .onChange(of: sessionTeardownCount) { _, _ in Task { await viewModel.refresh() } }
            // #826: mirrors Sudoku's `DailyHubView` picker — a past day with
            // >1 completed difficulty presents this instead of opening
            // directly (owner adjudication 2026-07-16).
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
                    // `.rawValue.capitalized` maps beginner/intermediate/expert →
                    // the existing "Beginner"/"Intermediate"/"Expert" L10n keys —
                    // byte-mirrors Sudoku's picker rows (whose capitalized
                    // rawValues likewise hit its "Easy"/"Medium"/"Hard" keys).
                    Button(LocalizedStringKey(choice.difficulty.rawValue.capitalized)) {
                        viewModel.reviewChoiceSelected(choice)
                    }
                }
            }
    }

    /// #1021 Phase B: the pure state → presentation mapping, recomputed every
    /// render from `viewModel`'s already-published, already-fetched state.
    private var todayPresentation: TodayPresentation<DailyCardModel> {
        MinesweeperTodayMapper.present(
            state: viewModel.state,
            inProgress: viewModel.inProgressSummary,
            isPhase2Degraded: viewModel.isPhase2Degraded
        )
    }

    private var headerModel: StreakHeaderModel {
        MinesweeperTodayMapper.headerModel(weekStrip: viewModel.weekStrip, allCompletedDays: viewModel.allCompletedDays)
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
            failure: { reason in
                // spacing-exempt: 12pt (icon/text stack gap) predates the
                // 5-tier `SpacingTokens` scale — no matching tier without
                // snapping and changing this screen's existing
                // layout/snapshot (#762 PR3).
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(theme.status.warning.resolved)
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(theme.text.secondary.resolved)
                }
            },
            onItemTap: { card in viewModel.cardTapped(card) },
            header: {
                // spacing-exempt: gap uses the same tier as the header's own
                // horizontal/top insets below — not a new spacing decision.
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
                            subtitle: String(localized: "Come back tomorrow for 3 new boards.", bundle: .main)
                        )
                    }
                }
                .padding(.horizontal, theme.spacing.medium)
                .padding(.top, theme.spacing.medium)
                // #935 batch 3: stable, loaded-hub root anchor (host-driven
                // XCUITest E2E, N13) — mirrors Sudoku's `DailyHubView`. A
                // zero-size marker composed via `.background` (a SIBLING
                // layer, not an ancestor of `StreakHeaderView`'s own pip
                // elements) so it cannot cascade an id onto them (#937's
                // "container id clobbers descendant ids" lesson).
                .background(alignment: .topLeading) {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("minesweeper.dailyHub.root")
                }
            },
            banner: { banner },
            loading: {
                ScrollView {
                    // spacing-exempt: 12pt matches `DailyHubShellView.cardGridGap`
                    // (predates the 5-tier scale) — kept identical so the
                    // skeleton grid's geometry is byte-for-byte the real grid's.
                    LazyVGrid(columns: skeletonColumns, spacing: 12) {
                        ForEach(MinesweeperTodayMapper.skeletonCards()) { model in
                            DailyCardContent(model: model)
                        }
                    }
                    .padding(theme.spacing.medium)
                }
            }
        )
    }

    private var skeletonColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible()),
            count: DailyHubGridLayout.columnCount(sizeClass: sizeClass, dynamicTypeSize: dynamicTypeSize)
        )
    }

    /// Translates the MS daily state into the generic shell input. MS has no
    /// `.exhausted` / `.failed` path (generation is pure + non-throwing), so
    /// only idle / loading / loaded are reachable.
    private var liftedState: HubLoadState<MinesweeperDailyCard> {
        switch viewModel.state {
        case .idle: return .idle
        case .loading: return .loading
        case .loaded(let cards): return .loaded(cards)
        }
    }
}

#Preview("MinesweeperDailyHub") {
    NavigationStack {
        MinesweeperDailyHubView(
            viewModel: MinesweeperDailyHubViewModel(path: .constant([]))
        )
    }
    .environment(\.theme, MinesweeperTheme())
}
