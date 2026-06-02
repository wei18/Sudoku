// NewGameView — Minesweeper's root content (difficulty picker + Start).
//
// Lives at the root of `MinesweeperRoot`'s NavigationStack. The user picks
// Beginner / Intermediate / Expert via a segmented `Picker`, then taps
// "Start" to push `AppRoute.board(difficulty:seed:)` onto the path. A fresh
// `UInt64` seed is generated per tap so successive Starts produce different
// boards (Daily-style date seeding is out of scope for Standard tier).

public import SwiftUI
public import MinesweeperEngine

public struct NewGameView: View {
    @Binding private var path: [AppRoute]
    @State private var difficulty: Difficulty

    public init(path: Binding<[AppRoute]>, initialDifficulty: Difficulty = .beginner) {
        self._path = path
        self._difficulty = State(initialValue: initialDifficulty)
    }

    public var body: some View {
        VStack(spacing: 24) {
            Text("New Game")
                .font(.largeTitle.weight(.semibold))

            Picker("Difficulty", selection: $difficulty) {
                ForEach(Difficulty.allCases, id: \.self) { level in
                    Text(displayName(level)).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Text(boardSummary(difficulty))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Button is a direct child of the VStack so the tap target is the
            // button's own rect (no parent gesture stealing) — swiftui-interaction
            // -footguns: tap-target shrink happens when Button sits inside a
            // Label / Stack that also reacts to tap. `.borderedProminent`
            // provides its own hit region; no `.contentShape` needed.
            Button(action: start) {
                Text("Start")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .accessibilityIdentifier("minesweeper.newGame.start")

            Spacer()
        }
        .padding(.top, 40)
        .navigationTitle("Minesweeper")
    }

    private func start() {
        path.append(Self.makeBoardRoute(difficulty: difficulty))
    }

    /// Builds the `.board` route for the given difficulty with a fresh random
    /// seed. Extracted for unit testing — see `NewGameViewTests`. Each call
    /// generates an independent `UInt64` so successive Starts produce
    /// different boards (collision prob ≈ 1 / 2^64 per call).
    internal static func makeBoardRoute(difficulty: Difficulty) -> AppRoute {
        let seed = UInt64.random(in: .min ... .max)
        return .board(difficulty: difficulty, seed: seed)
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

#Preview("NewGame") {
    NavigationStack {
        NewGameView(path: .constant([]))
    }
}
