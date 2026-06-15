// Game2048Theme — Tiles2048's concrete `Theme` palette.
//
// Warm-tile design: amber/saffron accent against cream paper; dark-mode
// goes deep mahogany. Complements the tile gradient without competing
// with it (tiles own the high-saturation warm surface; the chrome is muted).
//
// The generic `Theme` protocol + token value types + the `@Environment(\.theme)`
// key live in GameShellUI (#278 Tier-1 Phase 1); this file keeps 2048's
// CONCRETE values and conforms to that protocol.
//
// Changing any value here will churn the Game2048UITests snapshot baselines.

public import GameShellUI

public struct Game2048Theme: Theme {
    public init() {}

    public let surface = SurfaceTokens(
        background: ThemeColor(light: 0xFAF7F2, dark: 0x1A1410),
        primary: ThemeColor(light: 0xFFFFFF, dark: 0x241E18),
        elevated: ThemeColor(light: 0xFFFFFF, dark: 0x2C261E),
        placeholder: ThemeColor(light: 0xEDE8DF, dark: 0x2E2720)
    )

    public let text = TextTokens(
        primary: ThemeColor(light: 0x3D2B1F, dark: 0xF2EDE6),
        secondary: ThemeColor(light: 0x7A6A5A, dark: 0xAA9E92),
        tertiary: ThemeColor(light: 0xA8998A, dark: 0x7A6E64),
        given: ThemeColor(light: 0x3D2B1F, dark: 0xF2EDE6),
        user: ThemeColor(light: 0xD4812A, dark: 0xE8A055),
        errorDigit: ThemeColor(light: 0xC0392B, dark: 0xE06052)
    )

    public let accent = AccentTokens(
        primary: ThemeColor(light: 0xD4812A, dark: 0xE8A055),
        muted: ThemeColor(light: 0xF0DBBF, dark: 0x4A3826)
    )

    public let status = StatusTokens(
        success: ThemeColor(light: 0x27AE60, dark: 0x4DC97A),
        warning: ThemeColor(light: 0xD4812A, dark: 0xE8A055),
        error: ThemeColor(light: 0xC0392B, dark: 0xE06052)
    )

    public let difficulty = DifficultyTokens(
        easy: ThemeColor(light: 0xD4812A, dark: 0xE8A055),
        medium: ThemeColor(light: 0xC0711A, dark: 0xD4902E),
        hard: ThemeColor(light: 0xA0521A, dark: 0xC07838)
    )

    public let spacing = SpacingTokens()
}
