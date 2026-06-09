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

public struct MinesweeperPracticeHubView: View {
    @Binding private var path: [AppRoute]
    @State private var difficulty: Difficulty

    public init(path: Binding<[AppRoute]>, initialDifficulty: Difficulty = .beginner) {
        self._path = path
        self._difficulty = State(initialValue: initialDifficulty)
    }

    public var body: some View {
        PracticeHubShellView(
            title: "Practice",
            backgroundColor: .clear,
            filterHeader: "Difficulty",
            headerForeground: .primary,
            filter: { difficultyPicker },
            cta: { startCard }
        )
    }

    @ViewBuilder
    private var difficultyPicker: some View {
        Picker("Difficulty", selection: $difficulty) {
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

            Text(boardSummary(difficulty))
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

    private func displayName(_ level: Difficulty) -> String {
        switch level {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .expert: return "Expert"
        }
    }

    private func boardSummary(_ level: Difficulty) -> String {
        "\(level.rows) × \(level.columns) · \(level.mineCount) mines"
    }
}

#Preview("MinesweeperPracticeHub") {
    NavigationStack {
        MinesweeperPracticeHubView(path: .constant([]))
    }
}
