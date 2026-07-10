// MinesweeperPracticeHubView — Standard-tier Practice hub stub (PR U12).
//
// Wraps `GameShellUI.PracticeHubShellView` with a Difficulty Picker (filter
// slot) and a Start button (cta slot). Mirrors Sudoku's Practice hub shape
// per `feedback/minesweeper-mirrors-sudoku.md` but drops the shimmer state
// machine — MS has no async generator today, so the CTA pushes the route
// synchronously.

public import SwiftUI
internal import GameShellUI
public import MinesweeperEngine

public struct MinesweeperPracticeHubView<Banner: View>: View {
    @Binding private var path: [AppRoute]
    @State private var difficulty: Difficulty
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
            backgroundColor: .clear,
            filterHeader: "Difficulty",
            headerForeground: .primary,
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
        .padding(8)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    @ViewBuilder
    private var startCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ready to play")
                .font(.headline)

            boardSummary(difficulty)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: start) {
                Label("Start", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("minesweeper.practiceHub.start")
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
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
