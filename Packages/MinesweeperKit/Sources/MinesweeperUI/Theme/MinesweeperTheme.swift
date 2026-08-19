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
// tokens panel (the PROPOSED MS palette).
//
// #1015: every `ThemeColor` here now resolves via an Asset Catalog color set
// (`Resources/Colors.xcassets`, name = the dotted token path below) instead
// of a code-level light/dark hex branch — the OS resolves Light/Dark (and
// later Increased-Contrast) from the catalog. `light:`/`dark:` are still
// passed so `lightHex`/`darkHex` stay available to math-only consumers
// (`MinesweeperThemeContrastTests`) — the values must stay byte-identical to
// the color set's wells. Changing any value here will churn the MS snapshot
// baselines.

public import GameShellUI
internal import SwiftUI

public struct MinesweeperTheme: Theme {
    public init() {}

    public let surface = SurfaceTokens(
        background: ThemeColor(name: "surface.background", light: 0xF4F6F8, dark: 0x14171B, bundle: .module),
        primary: ThemeColor(name: "surface.primary", light: 0xFFFFFF, dark: 0x1C2026, bundle: .module),
        elevated: ThemeColor(name: "surface.elevated", light: 0xFFFFFF, dark: 0x242A32, bundle: .module),
        placeholder: ThemeColor(name: "surface.placeholder", light: 0xE6EAEE, dark: 0x272D35, bundle: .module)
    )

    public let cell = MinesweeperCellTokens(
        covered: ThemeColor(name: "cell.covered", light: 0xD6DEE6, dark: 0x2B333D, bundle: .module),
        revealed: ThemeColor(name: "cell.revealed", light: 0xFFFFFF, dark: 0x1C2026, bundle: .module),
        flagged: ThemeColor(name: "cell.flagged", light: 0xFBEBD8, dark: 0x3A2E1C, bundle: .module),
        mine: ThemeColor(name: "cell.mine", light: 0xFBE3E1, dark: 0x4A2724, bundle: .module),
        mineHit: ThemeColor(name: "cell.mineHit", light: 0xC8362B, dark: 0xE66258, bundle: .module),
        // #888 / #876 / #874 F-1: see MinesweeperCellTokens.flagInk doc.
        flagInk: ThemeColor(name: "cell.flagInk", light: 0x9C5C1C, dark: 0xE8A560, bundle: .module),
        // 1..8 neighbor-count glyphs. The prototype defines these as
        // single-value CSS vars (no light/dark companion); used identically
        // in both schemes, so each color set's Light/Dark wells repeat the
        // one hex.
        numbers: [
            ThemeColor(name: "cell.numbers.1", light: 0x3E6B8C, dark: 0x3E6B8C, bundle: .module), // 1
            ThemeColor(name: "cell.numbers.2", light: 0x1B7A3E, dark: 0x1B7A3E, bundle: .module), // 2
            ThemeColor(name: "cell.numbers.3", light: 0xC8362B, dark: 0xC8362B, bundle: .module), // 3
            ThemeColor(name: "cell.numbers.4", light: 0x5C4B9E, dark: 0x5C4B9E, bundle: .module), // 4
            ThemeColor(name: "cell.numbers.5", light: 0xA2845E, dark: 0xA2845E, bundle: .module), // 5
            ThemeColor(name: "cell.numbers.6", light: 0x2E8C9E, dark: 0x2E8C9E, bundle: .module), // 6
            ThemeColor(name: "cell.numbers.7", light: 0x1A1E24, dark: 0x1A1E24, bundle: .module), // 7
            ThemeColor(name: "cell.numbers.8", light: 0x868D95, dark: 0x868D95, bundle: .module), // 8
        ]
    )

    public let text = TextTokens(
        primary: ThemeColor(name: "text.primary", light: 0x1A1E24, dark: 0xEEF1F4, bundle: .module),
        secondary: ThemeColor(name: "text.secondary", light: 0x545B63, dark: 0xA4ACB4, bundle: .module),
        tertiary: ThemeColor(name: "text.tertiary", light: 0x868D95, dark: 0x767D85, bundle: .module),
        // No game-specific given/user/errorDigit distinction in MS; map to
        // the primary / accent / error tokens so the generic `Theme` contract
        // is satisfied without inventing unused MS semantics.
        given: ThemeColor(name: "text.given", light: 0x1A1E24, dark: 0xEEF1F4, bundle: .module),
        user: ThemeColor(name: "text.user", light: 0x3E6B8C, dark: 0x7FAFCF, bundle: .module),
        errorDigit: ThemeColor(name: "text.errorDigit", light: 0xC8362B, dark: 0xE66258, bundle: .module)
    )

    // celebratory (D1, #767 root-cause fix): must NOT reuse Sudoku's
    // 0xE0662E verbatim — MS's own `status.warning` is already orange
    // (0xD9822B), so that value would read as orange-on-orange and
    // reintroduce the confusion this fix removes. A redder, darker variant
    // separates by hue AND lightness. Dark value lifted with the same
    // dL/dS this theme's own warning ramp uses (0xD9822B -> 0xE8A560).
    public let accent = AccentTokens(
        primary: ThemeColor(name: "accent.primary", light: 0x3E6B8C, dark: 0x7FAFCF, bundle: .module),
        muted: ThemeColor(name: "accent.muted", light: 0xD5E2EC, dark: 0x2C4356, bundle: .module),
        celebratory: ThemeColor(name: "accent.celebratory", light: 0xD4501F, dark: 0xEB774C, bundle: .module)
    )

    public let status = StatusTokens(
        success: ThemeColor(name: "status.success", light: 0x1B7A3E, dark: 0x4BC579, bundle: .module),
        // Prototype's `--status-flag` (warning / flag accent).
        warning: ThemeColor(name: "status.warning", light: 0xD9822B, dark: 0xE8A560, bundle: .module),
        error: ThemeColor(name: "status.error", light: 0xC8362B, dark: 0xE66258, bundle: .module)
    )

    public let difficulty = DifficultyTokens(
        easy: ThemeColor(name: "difficulty.easy", light: 0x3E6B8C, dark: 0x7FAFCF, bundle: .module),   // Beginner
        medium: ThemeColor(name: "difficulty.medium", light: 0xC97D5F, dark: 0xD89A82, bundle: .module), // Intermediate
        hard: ThemeColor(name: "difficulty.hard", light: 0xB23A48, dark: 0xD96B77, bundle: .module)    // Expert
    )

    public let spacing = SpacingTokens()
}
