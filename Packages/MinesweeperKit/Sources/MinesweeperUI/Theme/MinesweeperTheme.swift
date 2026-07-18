// MinesweeperTheme — Minesweeper's concrete `Theme` palette (the cool
// "blueprint paper" / slate-blue design system; a sibling to Sudoku's sage /
// warm-paper, not a clone).
//
// The generic `Theme` protocol + token value types + the `@Environment(\.theme)`
// key live in GameShellUI (#278 Tier-1 Phase 1); this file keeps Minesweeper's
// CONCRETE values and conforms to that protocol. The MS-shaped board-cell
// tokens live in `MinesweeperCellTokens` (read via `\.minesweeperCell`), the
// same split Sudoku uses for `DefaultTheme` + `\.sudokuCell`.
//
// `public import GameShellUI` re-exports `Theme` + the token bundles through
// MinesweeperUI's public surface so MS views + `@testable import MinesweeperUI`
// tests keep resolving the theme types without an extra import.
//
// All hex values come from docs/minesweeper/minesweeper-app-flow.prototype.html
// tokens panel (the PROPOSED MS palette). Changing any value here will churn
// the MS snapshot baselines.

public import GameShellUI
internal import SwiftUI

public struct MinesweeperTheme: Theme {
    public init() {}

    public let surface = SurfaceTokens(
        background: ThemeColor(light: 0xF4F6F8, dark: 0x14171B),
        primary: ThemeColor(light: 0xFFFFFF, dark: 0x1C2026),
        elevated: ThemeColor(light: 0xFFFFFF, dark: 0x242A32),
        placeholder: ThemeColor(light: 0xE6EAEE, dark: 0x272D35)
    )

    public let cell = MinesweeperCellTokens(
        covered: ThemeColor(light: 0xD6DEE6, dark: 0x2B333D),
        revealed: ThemeColor(light: 0xFFFFFF, dark: 0x1C2026),
        flagged: ThemeColor(light: 0xFBEBD8, dark: 0x3A2E1C),
        mine: ThemeColor(light: 0xFBE3E1, dark: 0x4A2724),
        mineHit: ThemeColor(light: 0xC8362B, dark: 0xE66258),
        // #876 / #874 F-1: see MinesweeperCellTokens.lostMineFlagInk doc.
        lostMineFlagInk: ThemeColor(light: 0x9C5C1C, dark: 0xE8A560),
        // 1..8 neighbor-count glyphs. The prototype defines these as
        // single-value CSS vars (no light/dark companion); used identically
        // in both schemes, so each pair repeats the one hex.
        numbers: [
            ThemeColor(light: 0x3E6B8C, dark: 0x3E6B8C), // 1
            ThemeColor(light: 0x1B7A3E, dark: 0x1B7A3E), // 2
            ThemeColor(light: 0xC8362B, dark: 0xC8362B), // 3
            ThemeColor(light: 0x5C4B9E, dark: 0x5C4B9E), // 4
            ThemeColor(light: 0xA2845E, dark: 0xA2845E), // 5
            ThemeColor(light: 0x2E8C9E, dark: 0x2E8C9E), // 6
            ThemeColor(light: 0x1A1E24, dark: 0x1A1E24), // 7
            ThemeColor(light: 0x868D95, dark: 0x868D95), // 8
        ]
    )

    public let text = TextTokens(
        primary: ThemeColor(light: 0x1A1E24, dark: 0xEEF1F4),
        secondary: ThemeColor(light: 0x545B63, dark: 0xA4ACB4),
        tertiary: ThemeColor(light: 0x868D95, dark: 0x767D85),
        // No game-specific given/user/errorDigit distinction in MS; map to
        // the primary / accent / error tokens so the generic `Theme` contract
        // is satisfied without inventing unused MS semantics.
        given: ThemeColor(light: 0x1A1E24, dark: 0xEEF1F4),
        user: ThemeColor(light: 0x3E6B8C, dark: 0x7FAFCF),
        errorDigit: ThemeColor(light: 0xC8362B, dark: 0xE66258)
    )

    public let accent = AccentTokens(
        primary: ThemeColor(light: 0x3E6B8C, dark: 0x7FAFCF),
        muted: ThemeColor(light: 0xD5E2EC, dark: 0x2C4356)
    )

    public let status = StatusTokens(
        success: ThemeColor(light: 0x1B7A3E, dark: 0x4BC579),
        // Prototype's `--status-flag` (warning / flag accent).
        warning: ThemeColor(light: 0xD9822B, dark: 0xE8A560),
        error: ThemeColor(light: 0xC8362B, dark: 0xE66258)
    )

    public let difficulty = DifficultyTokens(
        easy: ThemeColor(light: 0x3E6B8C, dark: 0x7FAFCF),   // Beginner
        medium: ThemeColor(light: 0xC97D5F, dark: 0xD89A82), // Intermediate
        hard: ThemeColor(light: 0xB23A48, dark: 0xD96B77)    // Expert
    )

    public let spacing = SpacingTokens()
}
