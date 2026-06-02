// MinesweeperDailyHubView — Standard-tier Daily hub stub (PR U12).
//
// Wraps `GameShellUI.DailyHubShellView` with a placeholder data set so the
// shell renders a 1-or-3-column grid of three "today's boards" — mirroring
// Sudoku's Daily product per `feedback/minesweeper-mirrors-sudoku.md`. This
// stub proves the generic shell composes against a second consumer in-PR
// (the whole point of `feedback/reusable-targets-over-duplication.md`). It
// is intentionally shallow:
//   - No PuzzleProvider, no Persistence, no completion overlay. Real
//     "date-seeded board" generation + persisted completion land in a
//     follow-up MS Daily feature PR.
//   - The three cards are derived from the current calendar day (so the
//     content varies day-to-day in preview) but the underlying seed is
//     used as a display value only, not handed to the engine.
//   - Sidebar wiring into `MinesweeperRoot` is deferred — this view exists
//     to compile + render in `#Preview`.

public import SwiftUI
internal import GameShellUI
public import MinesweeperEngine

public struct MinesweeperDailyCard: Hashable, Sendable, Identifiable {
    public let difficulty: Difficulty
    public let seed: UInt64

    public var id: String { "\(difficulty.rawValue)-\(seed)" }

    public init(difficulty: Difficulty, seed: UInt64) {
        self.difficulty = difficulty
        self.seed = seed
    }
}

public struct MinesweeperDailyHubView: View {
    @Binding private var path: [AppRoute]
    private let date: Date

    public init(path: Binding<[AppRoute]>, date: Date = Date()) {
        self._path = path
        self.date = date
    }

    public var body: some View {
        DailyHubShellView(
            title: "Daily",
            backgroundColor: .clear,
            state: HubLoadState<MinesweeperDailyCard>.loaded(cards),
            card: { card in
                MinesweeperDailyCardView(card: card)
            },
            failure: { reason in
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            },
            onItemTap: { card in
                path.append(.board(difficulty: card.difficulty, seed: card.seed))
            }
        )
    }

    /// Three deterministic stub cards derived from the calendar day. Real
    /// date-seeded generation is a follow-up; this just proves the shell
    /// renders against a non-Sudoku Item type.
    private var cards: [MinesweeperDailyCard] {
        let day = Calendar(identifier: .gregorian)
            .ordinality(of: .day, in: .year, for: date) ?? 1
        let dayBase = UInt64(day)
        return [
            MinesweeperDailyCard(difficulty: .beginner, seed: dayBase &* 31),
            MinesweeperDailyCard(difficulty: .intermediate, seed: dayBase &* 131),
            MinesweeperDailyCard(difficulty: .expert, seed: dayBase &* 313),
        ]
    }
}

private struct MinesweeperDailyCardView: View {
    let card: MinesweeperDailyCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.3x3.fill")
                    .accessibilityHidden(true)
                Text(displayName(card.difficulty))
                    .font(.title3.weight(.medium))
                Spacer()
            }
            Text("Seed #\(card.seed)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func displayName(_ level: Difficulty) -> String {
        switch level {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .expert: return "Expert"
        }
    }
}

#Preview("MinesweeperDailyHub") {
    NavigationStack {
        MinesweeperDailyHubView(path: .constant([]))
    }
}
