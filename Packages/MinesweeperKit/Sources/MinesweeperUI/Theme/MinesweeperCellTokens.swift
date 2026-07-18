// MinesweeperCellTokens — Minesweeper's board-cell color tokens.
//
// The MS-side counterpart to Sudoku's `CellTokens` (#278 Tier-1 Phase 2b,
// 2026-06-03). The generic `Theme` protocol in GameShellUI is game-agnostic;
// board-cell tokens are app-SHAPED, so each app ships its own. Sudoku's are
// given / selected / error fills for a 9×9 grid; Minesweeper's are the
// covered / revealed / flagged / mine states + a 1–8 number palette for the
// neighbor-count glyphs.
//
// Views read these via `@Environment(\.minesweeperCell)`, injected at the same
// point the generic `\.theme` is injected: `MinesweeperAppComposition.rootView`
// (live) and `SnapshotConfig.hostingView` (snapshot tests). Mirrors the
// `\.sudokuCell` env key in `SudokuUI/Theme/CellTokens.swift`.
//
// All hex values come from docs/minesweeper/minesweeper-app-flow.prototype.html
// tokens panel (the PROPOSED MS palette). Changing any value will churn the MS
// snapshot baselines.

public import GameShellUI
public import SwiftUI

public struct MinesweeperCellTokens: Sendable, Equatable, Hashable {
    /// Hidden / not-yet-revealed cell background.
    public let covered: ThemeColor
    /// Revealed (safe) cell background.
    public let revealed: ThemeColor
    /// Flagged cell background (reserved — Tier-0 keeps flagged cells
    /// covered-style; defined here so the token set matches the prototype).
    public let flagged: ThemeColor
    /// Revealed-mine background, soft (non-detonated). Reserved until the
    /// engine distinguishes the detonated cell from other revealed mines.
    public let mine: ThemeColor
    /// Detonated-mine background (the cell the player hit). Bold red.
    public let mineHit: ThemeColor
    /// #876 / #874 F-1: ink for the flag glyph on a correctly-flagged mine
    /// surfaced at loss (`showsLostMine && cell.state == .flagged`) — the
    /// general `status.warning` flag ink contrast-fails against `mine` in
    /// light mode (2.39:1, below the WCAG 1.4.11 3:1 non-text floor) even
    /// though it's fine against the normal in-play `covered` fill. Same hue/
    /// saturation as `status.warning`, darkened (HSL L 0.51→0.36) for this
    /// one combination; dark reuses `status.warning`'s dark value verbatim
    /// (already 6.22:1, no regression). See design-system.md
    /// "Minesweeper board-cell token adjustments".
    public let lostMineFlagInk: ThemeColor

    /// Neighbor-count glyph palette, 1–8. Out-of-range counts fall back to the
    /// `8` color (the dimmest), matching the prototype's clamp.
    private let numbers: [ThemeColor]

    public init(
        covered: ThemeColor,
        revealed: ThemeColor,
        flagged: ThemeColor,
        mine: ThemeColor,
        mineHit: ThemeColor,
        lostMineFlagInk: ThemeColor,
        numbers: [ThemeColor]
    ) {
        self.covered = covered
        self.revealed = revealed
        self.flagged = flagged
        self.mine = mine
        self.mineHit = mineHit
        self.lostMineFlagInk = lostMineFlagInk
        self.numbers = numbers
    }

    /// The glyph color for a neighbor-mine `count` (1–8). Values outside
    /// 1...8 clamp to the nearest end of the palette.
    public func number(_ count: Int) -> ThemeColor {
        let index = min(max(count, 1), numbers.count) - 1
        return numbers[index]
    }
}

// MARK: - Environment key

private struct MinesweeperCellKey: EnvironmentKey {
    // Minesweeper's concrete cell palette. Apps inject the same value at their
    // root (`.environment(\.minesweeperCell, MinesweeperTheme().cell)`); this
    // default keeps un-injected previews legible rather than crashing.
    static let defaultValue = MinesweeperTheme().cell
}

public extension EnvironmentValues {
    var minesweeperCell: MinesweeperCellTokens {
        get { self[MinesweeperCellKey.self] }
        set { self[MinesweeperCellKey.self] = newValue }
    }
}
