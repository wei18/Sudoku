// CellTokens — Sudoku's board-cell color tokens.
//
// Moved out of GameShellUI's generic `Theme` protocol (#278 Tier-1 Phase 2a,
// 2026-06-03). These tokens are Sudoku-SHAPED (given / selected / error /
// notes-style fills for a 9×9 grid), so they don't belong on the game-agnostic
// base `Theme`. Minesweeper ships its OWN differently-shaped cell tokens in
// Phase 2b.
//
// Views read these via `@Environment(\.sudokuCell)`, injected at the same two
// points the generic `\.theme` is injected: `AppComposition.rootView` (live)
// and `SnapshotConfig.hostingView` (snapshot tests).

public import GameShellUI
public import SwiftUI

public struct CellTokens: Sendable, Equatable, Hashable {
    public let base: ThemeColor
    public let prefilled: ThemeColor
    public let userFilled: ThemeColor
    public let highlighted: ThemeColor
    public let selected: ThemeColor
    public let error: ThemeColor
    public let errorBorder: ThemeColor

    public init(
        base: ThemeColor,
        prefilled: ThemeColor,
        userFilled: ThemeColor,
        highlighted: ThemeColor,
        selected: ThemeColor,
        error: ThemeColor,
        errorBorder: ThemeColor
    ) {
        self.base = base
        self.prefilled = prefilled
        self.userFilled = userFilled
        self.highlighted = highlighted
        self.selected = selected
        self.error = error
        self.errorBorder = errorBorder
    }
}

// MARK: - Environment key

private struct SudokuCellKey: EnvironmentKey {
    // Sudoku's concrete cell palette. Apps inject the same value at their root
    // (`.environment(\.sudokuCell, DefaultTheme().cell)`); this default keeps
    // un-injected previews legible rather than crashing.
    static let defaultValue = DefaultTheme().cell
}

public extension EnvironmentValues {
    var sudokuCell: CellTokens {
        get { self[SudokuCellKey.self] }
        set { self[SudokuCellKey.self] = newValue }
    }
}
