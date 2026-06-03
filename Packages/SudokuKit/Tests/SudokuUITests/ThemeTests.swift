// Theme tokens vs docs/designs/design-system.md.
//
// Tests pin the canonical hex values per design system. Any change to a hex
// in DefaultTheme must be reflected here AND requires snapshot rebaselining
// (plan 8.11).

import GameShellUI  // #278 Tier-1 Phase 1: `Theme` protocol moved here.
import Testing
@testable import SudokuUI

@Suite("DefaultTheme — token values")
struct DefaultThemeTokenTests {

    @Test func accentMatchesDesignSystem() {
        let accent = DefaultTheme().accent.primary
        #expect(accent.lightHex == 0x5C7A4F)
        #expect(accent.darkHex == 0x9BB87E)
    }

    @Test func surfaceBackgroundMatchesDesignSystem() {
        let background = DefaultTheme().surface.background
        #expect(background.lightHex == 0xFAF8F3)
        #expect(background.darkHex == 0x15171A)
    }

    @Test func cellSelectedMatchesAccentMuted() {
        // design-system.md notes that `cell.selected` == `accent.muted`.
        let theme = DefaultTheme()
        #expect(theme.cell.selected.lightHex == theme.accent.muted.lightHex)
        #expect(theme.cell.selected.darkHex == theme.accent.muted.darkHex)
    }

    @Test func statusErrorMatchesDesignSystem() {
        let err = DefaultTheme().status.error
        #expect(err.lightHex == 0xC8362B)
        #expect(err.darkHex == 0xE66258)
    }

    @Test func spacingScaleMatchesGridUnit() {
        let spacing = DefaultTheme().spacing
        #expect(spacing.extraSmall == 4)
        #expect(spacing.small == 8)
        #expect(spacing.medium == 16)
        #expect(spacing.large == 24)
        #expect(spacing.extraLarge == 32)
    }
}

@Suite("Theme — protocol conformance")
struct ThemeConformanceTests {
    @Test func defaultThemeIsSendable() {
        // Compile-time: existential `any Theme` must cross actor boundaries.
        let theme: any Theme = DefaultTheme()
        _ = theme.accent.primary.lightHex
    }
}
