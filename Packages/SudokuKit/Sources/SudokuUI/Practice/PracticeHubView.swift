// PracticeHubView — difficulty density-preview cards + draw card + shimmer
// threshold.
//
// Per docs/designs/04-practice-hub.md + design.md v3 §3.2. The "New Game"
// CTA disables itself during draws; sub-100 ms draws skip indicators (no
// flash), >100 ms draws redact the puzzle-id hint (.redacted(reason:
// .placeholder)). #885 owner adjudication (2026-07-18): CTA label unified to
// "New Game" across both apps — was "Draw new puzzle" here, Sudoku-specific
// wording that would misdescribe Minesweeper's board generation.
//
// PR U12: outer VStack(24) + padding(16) + frame + chrome triple + inline
// "Difficulty" section header extracted into `GameShellUI.PracticeHubShellView`.
// #1021 Phase C: the segmented difficulty `Picker` (filter slot) is replaced
// by 3 `PracticeDifficultyCardView`s built from `SudokuPracticeCardsMapper`
// (design.md §3.2 density-preview thumbnails, representative sample —
// never the real next puzzle). Tapping a card only selects it
// (`viewModel.selectDifficulty`); it does not draw. `drawCard` (cta slot)
// keeps the existing 5-state `loadingState` → presentation mapping
// (idle/drawingQuiet/drawingShimmer/drawn/failed), now re-skinned onto
// `HubCard` (standard material) instead of a custom glass surface
// (design.md §4.2: content-layer cards don't get the Slider/Toggle glass
// exception).

public import MonetizationCore
public import SwiftUI
internal import GameShellUI
internal import SudokuEngine

public struct PracticeHubView<Banner: View>: View {
    @Bindable private var viewModel: PracticeHubViewModel
    @Environment(\.theme) private var theme
    private let banner: Banner
    // Gap between the 3 difficulty cards (#1021 Phase C) — content tier,
    // scales with Dynamic Type.
    @ScaledSpacing(.small) private var cardGap

    public init(
        viewModel: PracticeHubViewModel,
        @ViewBuilder banner: () -> Banner = { EmptyView() }
    ) {
        self.viewModel = viewModel
        self.banner = banner()
    }

    public var body: some View {
        PracticeHubShellView(
            title: "Practice",
            backgroundColor: theme.surface.background.resolved,
            filterHeader: "Difficulty",
            headerForeground: theme.text.primary.resolved,
            filter: { difficultyCards },
            cta: { drawCard },
            banner: { banner }
        )
    }

    @ViewBuilder
    private var difficultyCards: some View {
        // #1021 Phase C layout correction: stacked rows (design.md v3
        // prototype `.bcard` list), not a 3-column grid.
        VStack(spacing: cardGap) {
            ForEach(Difficulty.allCases, id: \.self) { difficulty in
                PracticeDifficultyCardView(
                    model: SudokuPracticeCardsMapper.card(for: difficulty),
                    isSelected: difficulty == viewModel.difficulty,
                    action: { viewModel.selectDifficulty(difficulty) }
                )
            }
        }
    }

    @ViewBuilder
    private var drawCard: some View {
        HubCard {
            // spacing-exempt: 12pt predates the 5-tier `SpacingTokens` scale —
            // no matching tier to route through without snapping to a neighbor
            // and changing this card's existing layout/snapshot. Tracked as a
            // follow-up once the token-scale gap gets an owner decision (#762 PR2).
            VStack(alignment: .leading, spacing: 12) {
                Text("Ready to play")
                    .font(.headline)
                    .foregroundStyle(theme.text.primary.resolved)

                hintRow

                Button {
                    // Single-tap: draw then push the board route. `playTapped`
                    // guards on `.drawn`, so a `.failed` draw leaves the user on
                    // the hub with the failure hint instead of pushing into a
                    // half-loaded board (see `hintRow` `.failed` branch for the
                    // visible affordance on draw failure). Issue #197: previously
                    // only `drawPuzzle` was called, leaving the puzzle id displayed
                    // inline with no affordance to navigate.
                    Task {
                        await viewModel.drawPuzzle()
                        viewModel.playTapped()
                    }
                } label: {
                    // #797 (CR round 2) fixed dark mode: the prominent style's
                    // default white label failed AA against EVERY difficulty tint
                    // there. #806 fixes the remaining light-mode residual —
                    // `surface.primary` alone is white in light mode, which still
                    // failed AA against medium (3.19:1) and hard (2.08:1) —
                    // switching to `onTintInk(for:)`, which picks whichever of
                    // `surface.primary`'s light/dark variants has the higher
                    // contrast against the ACTUAL resolved tint per mode. Full
                    // ratio table (WCAG relative-luminance) after the fix:
                    //   easy   — light 4.83 (white, unchanged) / dark 7.42 (navy)
                    //   medium — light 5.11 (navy, was 3.19 FAIL) / dark 6.89 (navy, unchanged)
                    //   hard   — light 7.85 (navy, was 2.08 FAIL) / dark 9.72 (navy, unchanged)
                    // Guarded by `ThemeTests.DifficultyTintOnTintInkContrastTests`.
                    // NOTE: the explicit ink applies ONLY while enabled — while
                    // `isDrawing` the button is `.disabled(...)` and an explicit
                    // `.foregroundStyle` would override the system's disabled
                    // dimming (caught by the committed shimmer baseline, which
                    // must stay byte-identical).
                    // #885 owner adjudication (2026-07-18): CTA wording unified
                    // with Minesweeper's Practice CTA — both apps now read
                    // "New Game" (was "Draw new puzzle" here, "Start" on MS).
                    if isDrawing {
                        Label("New Game", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("New Game", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(theme.surface.onTintInk(for: difficultyTint(for: viewModel.difficulty)))
                    }
                }
                .buttonStyle(.borderedProminent)
                // CTA carries the selected difficulty's tint, keeping the
                // difficulty cards and the draw button visually linked.
                .tint(tint(for: viewModel.difficulty))
                .controlSize(.large)
                .disabled(isDrawing)
                // #935 N1: was missing (MS's mirror CTA already carries
                // "minesweeper.practiceHub.start") — a host-driven XCUITest E2E
                // flow needs a stable, non-localized anchor to drive into
                // BoardLoaderView (the -uitest-loader-fail entry point).
                .accessibilityIdentifier("sudoku.practiceHub.start")
            }
        }
    }

    @ViewBuilder
    private var hintRow: some View {
        switch viewModel.loadingState {
        case .idle, .drawingQuiet:
            // #516: localize the difficulty (same `Easy/Medium/Hard` key the
            // Picker uses) + a localized "ready"; the "·" separator is verbatim.
            // Previously this interpolated the raw enum + literal "ready", so the
            // whole hint stayed English in non-en locales.
            Text("\(Text(LocalizedStringKey(viewModel.difficulty.rawValue.capitalized)))\(Text(verbatim: " · "))\(Text("ready"))")
                .font(.caption)
                .foregroundStyle(theme.text.secondary.resolved)
        case .drawingShimmer:
            Text("placeholder placeholder placeholder")
                .font(.caption)
                .redacted(reason: .placeholder)
                .accessibilityLabel("Loading")
                .accessibilityAddTraits(.updatesFrequently)
        case .drawn(let envelope):
            // #516: localize the difficulty; the "·" separator + deterministic
            // puzzleId (not user-facing copy) are verbatim.
            Text("\(Text(LocalizedStringKey(viewModel.difficulty.rawValue.capitalized)))\(Text(verbatim: " · \(envelope.identity.puzzleId)"))")
                .font(.caption)
                .foregroundStyle(theme.text.secondary.resolved)
        case .failed(let reason):
            Text(reason)
                .font(.caption)
                .foregroundStyle(theme.status.error.resolved)
                // #935 N3: stable, non-localized anchor for the draw-failure
                // caption (host-driven XCUITest E2E — see PracticeHubViewModel
                // `drawPuzzle()`'s catch branch).
                .accessibilityIdentifier("sudoku.practiceHub.failure")
        }
    }

    /// Map a `Difficulty` to its `difficulty.*` token.
    private func tint(for difficulty: Difficulty) -> Color {
        difficultyTint(for: difficulty).resolved
    }

    /// Same mapping as `tint(for:)` but keeping the unresolved `ThemeColor`
    /// (light + dark hex) — `onTintInk(for:)` needs both variants, not the
    /// pre-resolved `Color`.
    private func difficultyTint(for difficulty: Difficulty) -> ThemeColor {
        switch difficulty {
        case .easy: return theme.difficulty.easy
        case .medium: return theme.difficulty.medium
        case .hard: return theme.difficulty.hard
        }
    }

    private var isDrawing: Bool {
        switch viewModel.loadingState {
        case .drawingQuiet, .drawingShimmer: return true
        default: return false
        }
    }
}
