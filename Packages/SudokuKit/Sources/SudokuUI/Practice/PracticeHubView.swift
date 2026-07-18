// PracticeHubView — difficulty picker + draw card + shimmer threshold.
//
// Per docs/designs/04-practice-hub.md. The "New Game" CTA disables itself
// during draws; sub-100 ms draws skip indicators (no flash), >100 ms draws
// redact the puzzle-id hint (.redacted(reason: .placeholder)). #885 owner
// adjudication (2026-07-18): CTA label unified to "New Game" across both
// apps — was "Draw new puzzle" here, Sudoku-specific wording that would
// misdescribe Minesweeper's board generation.
//
// PR U12: outer VStack(24) + padding(16) + frame + chrome triple + inline
// "Difficulty" section header extracted into `GameShellUI.PracticeHubShellView`.
// This view now produces the difficulty Picker (filter slot) and the
// shimmer-aware `drawCard` (cta slot), and threads Sudoku theme colors
// (background + header foreground) into the shell. `headerForeground`
// preserves the previous `theme.text.primary.resolved` rendering →
// byte-identical to pre-U12 snapshots.

public import MonetizationCore
public import SwiftUI
internal import GameShellUI
internal import SudokuEngine

public struct PracticeHubView<Banner: View>: View {
    @Bindable private var viewModel: PracticeHubViewModel
    @Environment(\.theme) private var theme
    private let banner: Banner
    // Difficulty-picker card padding (#762 PR2 two-tier spacing contract) —
    // content tier, wraps the segmented Picker's text labels, scales with
    // Dynamic Type.
    @ScaledSpacing(.small) private var pickerCardPadding
    // Draw-card internal padding (#762 PR2 two-tier spacing contract) —
    // content tier, wraps the title/hint/button stack, scales with Dynamic
    // Type.
    @ScaledSpacing(.medium) private var drawCardPadding

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
            filter: { difficultyPicker },
            cta: { drawCard },
            banner: { banner }
        )
    }

    @ViewBuilder
    private var difficultyPicker: some View {
        Picker("Difficulty", selection: difficultyBinding) {
            ForEach(Difficulty.allCases, id: \.self) { difficulty in
                Text(LocalizedStringKey(difficulty.rawValue.capitalized))
                    .tag(difficulty)
            }
        }
        .pickerStyle(.segmented)
        // The "Difficulty" `Text` above is the section heading; the
        // Picker's own label would render again inline on macOS.
        .labelsHidden()
        // Tint the segmented control with the *selected* difficulty's
        // token so the active chip reads as that difficulty's color.
        // SwiftUI segmented Pickers don't expose per-segment tints,
        // so this is the closest we can get without a custom control.
        .tint(tint(for: viewModel.difficulty))
        .padding(pickerCardPadding)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private var difficultyBinding: Binding<Difficulty> {
        Binding(
            get: { viewModel.difficulty },
            set: { viewModel.selectDifficulty($0) }
        )
    }

    @ViewBuilder
    private var drawCard: some View {
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
            // segmented Picker and the draw button visually linked.
            .tint(tint(for: viewModel.difficulty))
            .controlSize(.large)
            .disabled(isDrawing)
        }
        .padding(drawCardPadding)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
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
