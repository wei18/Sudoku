// DefaultTheme — Sudoku's concrete `Theme` palette (the sage / warm-paper
// design system). The generic `Theme` protocol + token value types + the
// `@Environment(\.theme)` key moved to GameShellUI (#278 Tier-1 Phase 1);
// this file keeps Sudoku's CONCRETE values and conforms to that protocol.
//
// `public import GameShellUI` re-exports `Theme` + the token bundles through
// SudokuUI's public surface (same pattern as `RouteFactory.swift`), so
// SudokuUI views + `@testable import SudokuUI` tests keep resolving the
// theme types without an extra import.
//
// All hex values come from docs/designs/design-system.md §Color tokens.
// Changing any value here will churn snapshot baselines — coordinate with
// the snapshot baseline lock step (plan 8.11).

public import GameShellUI
internal import SwiftUI

public struct DefaultTheme: Theme {
    public init() {}

    public let surface = SurfaceTokens(
        background: ThemeColor(light: 0xFAF8F3, dark: 0x15171A),
        primary: ThemeColor(light: 0xFFFFFF, dark: 0x1E2024),
        elevated: ThemeColor(light: 0xFFFFFF, dark: 0x262A30),
        placeholder: ThemeColor(light: 0xEDEAE3, dark: 0x2A2D33)
    )

    public let cell = CellTokens(
        base: ThemeColor(light: 0xFFFFFF, dark: 0x1E2024),
        prefilled: ThemeColor(light: 0xEFEBE2, dark: 0x2A2D33),
        userFilled: ThemeColor(light: 0xFFFFFF, dark: 0x1E2024),
        highlighted: ThemeColor(light: 0xEBF0E2, dark: 0x252D1F),
        sameDigit: ThemeColor(light: 0xC8E1B4, dark: 0x2A3C20),
        selected: ThemeColor(light: 0xDCE6D0, dark: 0x3A4A30),
        error: ThemeColor(light: 0xFBE3E1, dark: 0x4A2724),
        errorBorder: ThemeColor(light: 0xC8362B, dark: 0xE66258)
    )

    public let text = TextTokens(
        primary: ThemeColor(light: 0x1A1D21, dark: 0xF2F3F5),
        secondary: ThemeColor(light: 0x54595F, dark: 0xA8ADB3),
        tertiary: ThemeColor(light: 0x86898E, dark: 0x787C82),
        given: ThemeColor(light: 0x1A1D21, dark: 0xF2F3F5),
        user: ThemeColor(light: 0x5C7A4F, dark: 0x9BB87E),
        errorDigit: ThemeColor(light: 0xA52A20, dark: 0xFF8077)
    )

    public let accent = AccentTokens(
        primary: ThemeColor(light: 0x5C7A4F, dark: 0x9BB87E),
        muted: ThemeColor(light: 0xDCE6D0, dark: 0x3A4A30)
    )

    public let status = StatusTokens(
        success: ThemeColor(light: 0x1B7A3E, dark: 0x4BC579),
        warning: ThemeColor(light: 0xA86A0E, dark: 0xE0A95C),
        error: ThemeColor(light: 0xC8362B, dark: 0xE66258)
    )

    public let difficulty = DifficultyTokens(
        easy: ThemeColor(light: 0x5C7A4F, dark: 0x9BB87E),
        medium: ThemeColor(light: 0xC97D5F, dark: 0xD89A82),
        hard: ThemeColor(light: 0xE6A857, dark: 0xEFC07F)
    )

    public let spacing = SpacingTokens()
}
