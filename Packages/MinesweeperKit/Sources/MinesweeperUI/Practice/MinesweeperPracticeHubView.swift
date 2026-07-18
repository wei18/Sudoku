// MinesweeperPracticeHubView — Standard-tier Practice hub stub (PR U12).
//
// Wraps `GameShellUI.PracticeHubShellView` with a Difficulty Picker (filter
// slot) and a "New Game" button (cta slot). Mirrors Sudoku's Practice hub
// shape per `feedback/minesweeper-mirrors-sudoku.md` but drops the shimmer
// state machine — MS has no async generator today, so the CTA pushes the
// route synchronously. #885 owner adjudication (2026-07-18): CTA label
// unified to "New Game" across both apps — was "Start" here, unlocalized
// (no catalog key existed); Sudoku's side was "Draw new puzzle", wording
// specific to puzzle generation that would misdescribe MS's board setup.

public import SwiftUI
internal import GameShellUI
public import MinesweeperEngine

public struct MinesweeperPracticeHubView<Banner: View>: View {
    @Binding private var path: [AppRoute]
    @State private var difficulty: Difficulty
    // #765: threads MS's theme through the hub, mirroring Sudoku's
    // `PracticeHubView` — see `tint(for:)` below.
    @Environment(\.theme) private var theme
    // #762 PR3: content-tier spacing (two-tier contract, design-system.md
    // §Spacing scale). Both wrap a control chip's own content (segmented
    // Picker / the "Ready to play" text+CTA stack), mirroring GameShellUI's
    // `HomeModeCard.cardPadding` precedent (PR1).
    @ScaledSpacing(.small) private var pickerPadding
    @ScaledSpacing(.medium) private var startCardPadding
    private let banner: Banner
    // #720 G2: fires when the player picks a new difficulty segment so the
    // composition root can persist it (mirrors Sudoku's
    // `PracticeHubViewModel.persistDifficulty`). `nil` (previews / most unit
    // tests) makes this a no-op.
    private let onDifficultyChanged: ((Difficulty) -> Void)?

    public init(
        path: Binding<[AppRoute]>,
        initialDifficulty: Difficulty = .beginner,
        onDifficultyChanged: ((Difficulty) -> Void)? = nil,
        @ViewBuilder banner: () -> Banner = { EmptyView() }
    ) {
        self._path = path
        self._difficulty = State(initialValue: initialDifficulty)
        self.onDifficultyChanged = onDifficultyChanged
        self.banner = banner()
    }

    public var body: some View {
        PracticeHubShellView(
            title: "Practice",
            backgroundColor: theme.surface.background.resolved,
            filterHeader: "Difficulty",
            headerForeground: theme.text.primary.resolved,
            filter: { difficultyPicker },
            cta: { startCard },
            banner: { banner }
        )
    }

    // #720 G2: `internal` (not `private`) so `MinesweeperPracticeHubViewTests`
    // can drive the persistence round trip directly — this repo's test infra
    // has no SwiftUI render-tree introspection (`AnyView`'s payload isn't
    // introspectable per `LiveRouteFactoryTests`), so the `Binding` itself is
    // the seam under test. Mirrors Sudoku's `PracticeHubView.difficultyBinding`,
    // which routes through `viewModel.selectDifficulty(_:)` instead.
    var difficultyBinding: Binding<Difficulty> {
        Binding(
            get: { difficulty },
            set: { newValue in
                difficulty = newValue
                onDifficultyChanged?(newValue)
            }
        )
    }

    @ViewBuilder
    private var difficultyPicker: some View {
        Picker("Difficulty", selection: difficultyBinding) {
            ForEach(Difficulty.allCases, id: \.self) { level in
                Text(displayName(level)).tag(level)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        // #765: tint the segmented control with the *selected* difficulty's
        // token so the active chip reads as that difficulty's color, mirroring
        // Sudoku's `PracticeHubView.difficultyPicker`.
        .tint(tint(for: difficulty))
        // #762 PR3: content tier (chip padding around the Picker's own
        // text/segments) — 8 matches `SpacingTokens.small`.
        .padding(pickerPadding)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    @ViewBuilder
    private var startCard: some View {
        // spacing-exempt: 12pt (text/CTA stack gap) predates the 5-tier
        // `SpacingTokens` scale — no matching tier without snapping and
        // changing this card's existing layout/snapshot (#762 PR3).
        VStack(alignment: .leading, spacing: 12) {
            Text("Ready to play")
                .font(.headline)
                .foregroundStyle(theme.text.primary.resolved)

            boardSummary(difficulty)
                .font(.caption)
                .foregroundStyle(theme.text.secondary.resolved)

            Button(action: start) {
                // #797 (CR round 2) fixed dark mode, mirroring Sudoku's
                // PracticeHubView draw CTA: the prominent style's default
                // white label failed AA against every difficulty tint there.
                // #806 fixes the remaining light-mode residual —
                // `surface.primary` alone is white in light mode, which still
                // failed AA against Intermediate (3.19:1) — switching to
                // `onTintInk(for:)`, which picks whichever of
                // `surface.primary`'s light/dark variants has the higher
                // contrast against the ACTUAL resolved tint per mode. Full
                // ratio table (WCAG relative-luminance) after the fix:
                //   Beginner     — light 5.70 (white, unchanged) / dark 6.96 (navy)
                //   Intermediate — light 5.13 (navy, was 3.19 FAIL) / dark 6.90 (navy, unchanged)
                //   Expert       — light 5.85 (white, unchanged) / dark 4.92 (navy, unchanged)
                // Guarded by `MinesweeperThemeContrastTests.DifficultyTintOnTintInkContrastTests`.
                // #885 owner adjudication (2026-07-18): CTA wording unified
                // with Sudoku's Practice CTA — both apps now read "New Game"
                // (was "Start" here, "Draw new puzzle" on Sudoku).
                Label("New Game", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(theme.surface.onTintInk(for: difficultyTint(for: difficulty)))
            }
            .buttonStyle(.borderedProminent)
            // #765: CTA carries the selected difficulty's tint, keeping the
            // segmented Picker and the start button visually linked (mirrors
            // Sudoku's `drawCard`).
            .tint(tint(for: difficulty))
            .controlSize(.large)
            .accessibilityIdentifier("minesweeper.practiceHub.start")
        }
        // #762 PR3: content tier (card padding around the text+CTA stack) —
        // 16 matches `SpacingTokens.medium`, mirrors `HomeModeCard.cardPadding`.
        .padding(startCardPadding)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
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
        case .beginner: return theme.difficulty.easy
        case .intermediate: return theme.difficulty.medium
        case .expert: return theme.difficulty.hard
        }
    }

    private func start() {
        let seed = UInt64.random(in: .min ... .max)
        path.append(.board(difficulty: difficulty, seed: seed, mode: .practice))
    }

    // #623: returns `LocalizedStringKey` (not a verbatim `String`) so the
    // difficulty name is localized via the catalog — mirrors the Daily hub's
    // `displayName` and Sudoku's `LocalizedStringKey(difficulty.rawValue…)`.
    private func displayName(_ level: Difficulty) -> LocalizedStringKey {
        switch level {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .expert: return "Expert"
        }
    }

    // #595: the whole hint is one localized key `"%lld × %lld · %lld mines"` so the
    // "mines" word is translated (the `× / ·` + dimensions carry through every
    // locale). MS mine counts are always ≥ 10 (beginner 10 / intermediate 40 /
    // expert 99), so a non-plural key is grammatically correct everywhere.
    private func boardSummary(_ level: Difficulty) -> Text {
        Text("\(level.rows) × \(level.columns) · \(level.mineCount) mines")
    }
}

#Preview("MinesweeperPracticeHub") {
    NavigationStack {
        MinesweeperPracticeHubView(path: .constant([]))
    }
}
