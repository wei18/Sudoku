// MinesweeperPracticeCardsMapper — builds the 3 `PracticeCardModel`s for the
// Practice hub's difficulty cards (#1021 Phase C, design.md §3.2).
//
// Board shape + mine count come straight from `MinesweeperEngine.Difficulty`
// (never a hard-coded copy) so a future preset change can't silently drift
// the thumbnail out of sync with the real board. The thumbnail itself is a
// deterministic sample (`BoardPreview.densitySample`), never the actual next
// board — see `BoardPreview+DensitySample.swift`'s header for why.

internal import GameShellUI
internal import MinesweeperEngine

enum MinesweeperPracticeCardsMapper {
    /// One fixed seed per difficulty so the sample thumbnail is stable
    /// across launches and snapshots (arbitrary constants — carry no
    /// relationship to real board seeds).
    private static func seed(for difficulty: Difficulty) -> UInt64 {
        switch difficulty {
        case .beginner: return 1_021_011
        case .intermediate: return 1_021_012
        case .expert: return 1_021_013
        }
    }

    private static func pipLevel(for difficulty: Difficulty) -> Int {
        switch difficulty {
        case .beginner: return 1
        case .intermediate: return 2
        case .expert: return 3
        }
    }

    /// Reuses the same catalog keys the difficulty picker already renders
    /// ("Beginner" / "Intermediate" / "Expert").
    private static func title(for difficulty: Difficulty) -> String {
        switch difficulty {
        case .beginner: return String(localized: "Beginner")
        case .intermediate: return String(localized: "Intermediate")
        case .expert: return String(localized: "Expert")
        }
    }

    /// Reuses the existing "%lld × %lld · %lld mines" catalog key (already
    /// shipped via `MinesweeperPracticeHubView.boardSummary`'s `Text`
    /// interpolation) — same row/column/mine order.
    private static func detail(for difficulty: Difficulty) -> String {
        String(localized: "\(difficulty.rows) × \(difficulty.columns) · \(difficulty.mineCount) mines")
    }

    static func card(for difficulty: Difficulty) -> PracticeCardModel {
        let fillRatio = Double(difficulty.mineCount) / Double(difficulty.cellCount)
        let preview = BoardPreview.densitySample(
            columns: difficulty.columns,
            rows: difficulty.rows,
            fillRatio: fillRatio,
            mark: .marked,
            seed: seed(for: difficulty)
        ) ?? BoardPreview(
            columns: difficulty.columns,
            rows: difficulty.rows,
            cells: Array(repeating: .empty, count: difficulty.cellCount)
        )!

        return PracticeCardModel(
            id: difficulty.rawValue,
            title: title(for: difficulty),
            pipLevel: pipLevel(for: difficulty),
            detail: detail(for: difficulty),
            preview: preview
        )
    }

    static func cards() -> [PracticeCardModel] {
        Difficulty.allCases.map(card(for:))
    }
}
