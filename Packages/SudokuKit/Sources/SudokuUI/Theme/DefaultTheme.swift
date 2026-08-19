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
//
// #1015: every `ThemeColor` here now resolves via an Asset Catalog color set
// (`Resources/Colors.xcassets`, name = the dotted token path below) instead
// of a code-level light/dark hex branch — the OS resolves Light/Dark (and
// later Increased-Contrast) from the catalog. `light:`/`dark:` are still
// passed so `lightHex`/`darkHex` stay available to math-only consumers
// (`ThemeTests`, `onTintInk`) — the values must stay byte-identical to the
// color set's wells; changing either one without the other reintroduces
// drift. Changing any value here will churn snapshot baselines — coordinate
// with the snapshot baseline lock step (plan 8.11).

public import GameShellUI
internal import SwiftUI

public struct DefaultTheme: Theme {
    public init() {}

    public let surface = SurfaceTokens(
        background: ThemeColor(name: "surface.background", light: 0xFAF8F3, dark: 0x15171A, bundle: .module),
        primary: ThemeColor(name: "surface.primary", light: 0xFFFFFF, dark: 0x1E2024, bundle: .module),
        elevated: ThemeColor(name: "surface.elevated", light: 0xFFFFFF, dark: 0x262A30, bundle: .module),
        placeholder: ThemeColor(name: "surface.placeholder", light: 0xEDEAE3, dark: 0x2A2D33, bundle: .module)
    )

    public let cell = CellTokens(
        base: ThemeColor(name: "cell.base", light: 0xFFFFFF, dark: 0x1E2024, bundle: .module),
        prefilled: ThemeColor(name: "cell.prefilled", light: 0xEFEBE2, dark: 0x2A2D33, bundle: .module),
        userFilled: ThemeColor(name: "cell.userFilled", light: 0xFFFFFF, dark: 0x1E2024, bundle: .module),
        highlighted: ThemeColor(name: "cell.highlighted", light: 0xEBF0E2, dark: 0x252D1F, bundle: .module),
        sameDigit: ThemeColor(name: "cell.sameDigit", light: 0xC8E1B4, dark: 0x2A3C20, bundle: .module),
        selected: ThemeColor(name: "cell.selected", light: 0xDCE6D0, dark: 0x3A4A30, bundle: .module),
        // #850: retuned so the error wash out-weighs `sameDigit` green
        // (light 1.56:1 vs. 1.41:1; dark 1.43:1 vs. 1.37:1 against the
        // respective base cell) — see docs/designs/design-system.md
        // §Color tokens and #850 designer spec for the WCAG math.
        error: ThemeColor(name: "cell.error", light: 0xF2C4C0, dark: 0x602924, bundle: .module),
        errorBorder: ThemeColor(name: "cell.errorBorder", light: 0xC8362B, dark: 0xE66258, bundle: .module)
    )

    public let text = TextTokens(
        primary: ThemeColor(name: "text.primary", light: 0x1A1D21, dark: 0xF2F3F5, bundle: .module),
        secondary: ThemeColor(name: "text.secondary", light: 0x54595F, dark: 0xA8ADB3, bundle: .module),
        tertiary: ThemeColor(name: "text.tertiary", light: 0x86898E, dark: 0x787C82, bundle: .module),
        given: ThemeColor(name: "text.given", light: 0x1A1D21, dark: 0xF2F3F5, bundle: .module),
        user: ThemeColor(name: "text.user", light: 0x5C7A4F, dark: 0x9BB87E, bundle: .module),
        errorDigit: ThemeColor(name: "text.errorDigit", light: 0xA52A20, dark: 0xFF8077, bundle: .module)
    )

    // celebratory (D1, #767 root-cause fix): "charcoal orange" — separates by
    // both hue and lightness from `status.warning` (0xA86A0E light /
    // 0xE0A95C dark) and from `accent.primary`'s sage entirely. Dark value
    // lightens in the same family as the other ramps (see e.g.
    // difficulty.hard 0xE6A857 -> 0xEFC07F), keeping roughly the same ~17°
    // hue gap from warning that the approved light value has.
    public let accent = AccentTokens(
        primary: ThemeColor(name: "accent.primary", light: 0x5C7A4F, dark: 0x9BB87E, bundle: .module),
        muted: ThemeColor(name: "accent.muted", light: 0xDCE6D0, dark: 0x3A4A30, bundle: .module),
        celebratory: ThemeColor(name: "accent.celebratory", light: 0xE0662E, dark: 0xEB8F65, bundle: .module)
    )

    public let status = StatusTokens(
        success: ThemeColor(name: "status.success", light: 0x1B7A3E, dark: 0x4BC579, bundle: .module),
        warning: ThemeColor(name: "status.warning", light: 0xA86A0E, dark: 0xE0A95C, bundle: .module),
        error: ThemeColor(name: "status.error", light: 0xC8362B, dark: 0xE66258, bundle: .module)
    )

    public let difficulty = DifficultyTokens(
        easy: ThemeColor(name: "difficulty.easy", light: 0x5C7A4F, dark: 0x9BB87E, bundle: .module),
        medium: ThemeColor(name: "difficulty.medium", light: 0xC97D5F, dark: 0xD89A82, bundle: .module),
        hard: ThemeColor(name: "difficulty.hard", light: 0xE6A857, dark: 0xEFC07F, bundle: .module)
    )

    public let spacing = SpacingTokens()
}
