// MinesweeperDailyHubView — date-seeded Daily hub (#290).
//
// Real daily content, replacing the PR U12 placeholder. Mirrors Sudoku's
// `DailyHubView`: produces the game-specific `MinesweeperDailyCard` items +
// MS theme colors and hands them to the generic `GameShellUI.DailyHubShellView`.
// `.task { bootstrap() }` stays on the caller (shells own no side-effect
// modifiers — X4 / SettingsShellView precedent).
//
// The daily trio = one date-seeded board per difficulty (beginner /
// intermediate / expert), the same three boards for everyone on a given UTC
// day, rolling over at UTC midnight. Tapping a card pushes `.board(...)` with
// the daily seed. Completed cards show a checkmark (driven off
// `PersistenceProtocol.fetchCompletedDailyIds`; parity-only until MS daily
// save-flow lands).

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

    public init(
        viewModel: MinesweeperDailyHubViewModel,
        @ViewBuilder banner: () -> Banner = { EmptyView() }
    ) {
        _viewModel = State(wrappedValue: viewModel)
        self.banner = banner()
    }

    public var body: some View {
        // #840: the week strip is injected into `DailyHubShellView`'s
        // `header` slot (GameShellKit stays untouched — see
        // `MinesweeperDailyStripView`'s header comment on the "no shared
        // widget" scope note) instead of sitting as a fixed sibling above
        // the shell (#774's original placement — owner-reported regression:
        // the trio scrolled UNDER a pinned strip). The shell renders
        // `header` in every load state, so it still can't disappear.
        // Mirrors Sudoku's `DailyHubView`.
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

    private var dailyHubShell: some View {
        DailyHubShellView(
            title: "Daily",
            backgroundColor: theme.surface.background.resolved,
            state: liftedState,
            card: { card in MinesweeperDailyCardView(card: card, isPending: viewModel.isPhase2Pending) },
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
                MinesweeperDailyStripView(snapshot: viewModel.weekStrip, onDayTap: { day in viewModel.dayTapped(day) })
                    .padding(.horizontal, theme.spacing.medium)
                    .padding(.top, theme.spacing.medium)
            },
            banner: { banner }
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

// #886: widened from `private` to internal (module-default access) so
// `MinesweeperDailyCardView.accessibilityDescription(...)` is directly
// unit-testable via `@testable import MinesweeperUI` — mirrors Sudoku's
// `DailyPuzzleCard`, which was already internal for the same reason.
struct MinesweeperDailyCardView: View {
    let card: MinesweeperDailyCard
    /// #878 (#874 F-4): mirrors Sudoku's `DailyPuzzleCard.isPending` exactly
    /// — `true` while the hub's phase-2 completion-overlay fetch is in
    /// flight (`MinesweeperDailyHubViewModel.isPhase2Pending`, which already
    /// no-ops `cardTapped` during this window, #842). Re-opens #842's
    /// adjudicated "no visual affordance" tradeoff with the #874 audit's
    /// evidence. Smallest mirror-consistent fix — dim the card content and
    /// drop the `.isButton` trait, no spinner (#843 no-skeleton stance).
    var isPending: Bool = false
    @Environment(\.theme) private var theme
    // #762 PR3: content tier (two-tier contract, design-system.md §Spacing
    // scale). Both wrap the card's own header row / caption stack — 8
    // matches `SpacingTokens.small`; shared since both call sites use the
    // same tier.
    @ScaledSpacing(.small) private var contentGap
    // Card outer padding — mirrors GameShellUI's `HomeModeCard.cardPadding`
    // precedent (PR1): 16 matches `SpacingTokens.medium`.
    @ScaledSpacing(.medium) private var cardPadding

    var body: some View {
        VStack(alignment: .leading, spacing: contentGap) {
            HStack(spacing: contentGap) {
                Circle()
                    .fill(difficultyTint)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(displayName(card.difficulty))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(difficultyTint)
                Spacer()
                if card.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.status.success.resolved)
                        .font(.callout)
                } else if card.isFailed {
                    // Epic 8 (SDD-003): third state — mine hit on this daily.
                    // "Replay" affordance is communicated by the tap action.
                    Label {
                        Text("Failed")
                    } icon: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .font(.callout)
                    .foregroundStyle(theme.status.warning.resolved)
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
            // second line and Sudoku's decorative `MiniBoardStrip` used to
            // diverge (MS: real "16 × 16 · 40 mines" board-spec text;
            // Sudoku: zero-data-binding decoration) — now unified to the
            // same real per-difficulty stat on both cards. Owner-accepted
            // tradeoff: board dimensions no longer surface on the hub card
            // (still visible in the difficulty picker / board itself).
            Text("Best \(MinesweeperStatsTileView.timeLabel(card.bestTimeSeconds))")
                .font(.caption)
                .foregroundStyle(theme.text.secondary.resolved)
        }
        // #878: subtle pending dim — content only, the glass card shape/
        // background stays at full opacity so the row doesn't look broken.
        // Mirrors Sudoku's `DailyPuzzleCard`.
        .opacity(isPending ? Self.pendingOpacity : 1)
        .padding(cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        // `.contentShape(Rectangle())` BEFORE `.glassEffect(...)` so the whole
        // card frame (incl. padding) is tap-hittable on macOS — mirrors
        // Sudoku's DailyPuzzleCard / HomeView card ordering (issue #15 / #197).
        .contentShape(Rectangle())
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        // #886: switched from `.combine` to an explicit composed label
        // (mirrors `MinesweeperStatsTileView`'s identical "dot + difficulty
        // name + stat" shape) — `.combine`'s implicit child concatenation is
        // why the board-spec/best-time line was never announced before; the
        // checkmark/Failed icons' own `.accessibilityLabel` moved into
        // `accessibilityDescription` below instead of being combine-concatenated.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        // #878: mirrors Sudoku's `DailyPuzzleCard` — while pending the tap
        // gate makes this row genuinely inert (`cardTapped` no-ops), so drop
        // `.isButton` instead of promising an action VoiceOver's double-tap
        // won't honor yet. Same #826 `isTappable` precedent; label text
        // unchanged.
        .accessibilityAddTraits(isPending ? [] : .isButton)
    }

    /// #878: subtle-dim opacity for the pending treatment above — mirrors
    /// Sudoku's `DailyPuzzleCard.pendingOpacity` exactly.
    private static let pendingOpacity: Double = 0.5

    /// Map `Difficulty` to a `difficulty.*` theme token. Exhaustive — adding a
    /// case forces this to update (mirrors Sudoku's `difficultyTint`).
    private var difficultyTint: Color {
        switch card.difficulty {
        case .beginner: return theme.difficulty.easy.resolved
        case .intermediate: return theme.difficulty.medium.resolved
        case .expert: return theme.difficulty.hard.resolved
        }
    }

    /// The localized difficulty name's catalog key — shared between
    /// `displayName` (SwiftUI `LocalizedStringKey`, visual) and
    /// `accessibilityDescription` (plain `String` lookup via `Bundle.main`).
    private static func nameKey(_ level: Difficulty) -> String {
        switch level {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .expert: return "Expert"
        }
    }

    private func displayName(_ level: Difficulty) -> LocalizedStringKey {
        LocalizedStringKey(Self.nameKey(level))
    }

    private var accessibilityDescription: String {
        Self.accessibilityDescription(
            difficulty: card.difficulty,
            isCompleted: card.isCompleted,
            isFailed: card.isFailed,
            bestTimeSeconds: card.bestTimeSeconds
        )
    }

    /// #886: combined VoiceOver label — mirror of Sudoku's
    /// `DailyPuzzleCard.accessibilityDescription`, extended with MS's third
    /// `isFailed` state (not in the #886 spec's Sudoku-only examples, since
    /// Sudoku has no equivalent — reuses the existing "Failed" key already
    /// used at this call site pre-#886, so VoiceOver keeps hearing it after
    /// the `.combine` → explicit-label switch instead of silently losing it).
    /// No new a11y keys: "Completed" / "Failed" / "best time %@" / "no best
    /// time yet" all pre-exist in the MS catalog. A `static func` (not a
    /// `private var`), mirroring `MinesweeperStatsTileView.timeLabel`/
    /// `spokenTime`, so tests can pin the composed string directly without
    /// standing up a `View`'s `@Environment` context.
    static func accessibilityDescription(
        difficulty: Difficulty,
        isCompleted: Bool,
        isFailed: Bool,
        bestTimeSeconds: Int?
    ) -> String {
        let key = nameKey(difficulty)
        let name = Bundle.main.localizedString(forKey: key, value: key, table: nil)
        var parts = [name]
        if isCompleted {
            parts.append(String(localized: "Completed", bundle: .main))
        } else if isFailed {
            parts.append(String(localized: "Failed", bundle: .main))
        }
        if let best = bestTimeSeconds {
            parts.append(String(localized: "best time \(MinesweeperStatsTileView.spokenTime(best))", bundle: .main))
        } else {
            parts.append(String(localized: "no best time yet", bundle: .main))
        }
        return parts.joined(separator: ", ")
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
