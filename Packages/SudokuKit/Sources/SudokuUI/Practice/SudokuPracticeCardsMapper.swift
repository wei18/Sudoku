// SudokuPracticeCardsMapper — builds the 3 `PracticeCardModel`s for the
// Practice hub's difficulty cards (#1021 Phase C, design.md §3.2).
//
// Givens counts (40 / 33 / 26 out of 81) are the midpoint-ish representative
// values inside each `PuzzleCalibrator` clue band (Easy 32-50, Medium 28-38,
// Hard 22-32) — NOT the actual next puzzle's clue count. The thumbnail is a
// deterministic sample (`BoardPreview.densitySample`), picked purely to
// communicate density; it must never be mistaken for (or move forward) the
// real draw (design.md §3.2 explicit rationale, mirrored in
// `BoardPreview+DensitySample.swift`'s header).

internal import GameShellUI
internal import SudokuEngine

enum SudokuPracticeCardsMapper {
    /// Sudoku board shape for every difficulty's thumbnail — always the
    /// real 9×9 grid (never scaled down further).
    private static let boardSize = 9

    /// One fixed seed per difficulty so the sample thumbnail is stable
    /// across launches and snapshots (arbitrary constants — carry no
    /// relationship to real puzzle seeds).
    private static func seed(for difficulty: Difficulty) -> UInt64 {
        switch difficulty {
        case .easy: return 1_021_001
        case .medium: return 1_021_002
        case .hard: return 1_021_003
        }
    }

    /// Representative givens count per difficulty (design.md §3.2 / PR
    /// dispatch spec) — inside `PuzzleCalibrator`'s accepted clue band for
    /// that difficulty, never the actual next puzzle's count.
    private static func representativeGivens(for difficulty: Difficulty) -> Int {
        switch difficulty {
        case .easy: return 40
        case .medium: return 33
        case .hard: return 26
        }
    }

    private static func pipLevel(for difficulty: Difficulty) -> Int {
        switch difficulty {
        case .easy: return 1
        case .medium: return 2
        case .hard: return 3
        }
    }

    /// Reuses the same catalog keys the difficulty picker already renders
    /// (`LocalizedStringKey(difficulty.rawValue.capitalized)` → "Easy" /
    /// "Medium" / "Hard").
    private static func title(for difficulty: Difficulty) -> String {
        switch difficulty {
        case .easy: return String(localized: "Easy", bundle: .main)
        case .medium: return String(localized: "Medium", bundle: .main)
        case .hard: return String(localized: "Hard", bundle: .main)
        }
    }

    private static func detail(for difficulty: Difficulty) -> String {
        let givens = representativeGivens(for: difficulty)
        return String(localized: "~\(givens) givens", bundle: .main)
    }

    static func card(for difficulty: Difficulty) -> PracticeCardModel {
        let givens = representativeGivens(for: difficulty)
        let fillRatio = Double(givens) / Double(boardSize * boardSize)
        // #1021 CR2 MINOR: `densitySample` only returns `nil` for
        // non-positive `columns`/`rows` (see its own doc) — `boardSize` (9)
        // is a fixed positive constant, so this branch is structurally
        // unreachable. `guard let ... else { preconditionFailure }` documents
        // that invariant with a clear crash message instead of the previous
        // `?? BoardPreview(...)!` — a force-unwrapped SECOND fallback
        // construction that duplicated the "empty board" shape for no
        // reachable case.
        guard let preview = BoardPreview.densitySample(
            columns: boardSize,
            rows: boardSize,
            fillRatio: fillRatio,
            mark: .given,
            seed: seed(for: difficulty)
        ) else {
            preconditionFailure("BoardPreview.densitySample only fails for non-positive dims; boardSize is fixed positive")
        }

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
