// Theme tokens vs docs/designs/design-system.md.
//
// Tests pin the canonical hex values per design system. Any change to a hex
// in DefaultTheme must be reflected here AND requires snapshot rebaselining
// (plan 8.11).

import Foundation  // #797: `pow` for the WCAG luminance math below.
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

// MARK: - On-accent-ink contract (#786/#797)

/// Guards the `SurfaceTokens.primary` on-accent-ink contract (see its doc in
/// GameShellUI/Theme.swift): `surface.primary` is the ink every prominent
/// accent-filled control uses, so it must clear WCAG AA (≥ 4.5:1) against
/// `accent.primary` in both modes. A future palette tweak that silently drops
/// below AA fails here instead of shipping (the exact defect class #786/#797
/// fixed by hand). Luminance math is the standard WCAG 2.x relative-luminance
/// formula, inlined per instruction (no new shared test target).
@Suite("DefaultTheme — on-accent ink contrast (#797)")
struct DefaultThemeOnAccentContrastTests {

    private func linearize(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    private func relativeLuminance(_ hex: UInt32) -> Double {
        let red = linearize(Double((hex >> 16) & 0xFF) / 255)
        let green = linearize(Double((hex >> 8) & 0xFF) / 255)
        let blue = linearize(Double(hex & 0xFF) / 255)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    private func contrastRatio(_ first: UInt32, _ second: UInt32) -> Double {
        let lumA = relativeLuminance(first)
        let lumB = relativeLuminance(second)
        return (max(lumA, lumB) + 0.05) / (min(lumA, lumB) + 0.05)
    }

    @Test func surfacePrimaryOnAccentPrimaryClearsAAInBothModes() {
        let theme = DefaultTheme()
        let light = contrastRatio(theme.surface.primary.lightHex, theme.accent.primary.lightHex)
        let dark = contrastRatio(theme.surface.primary.darkHex, theme.accent.primary.darkHex)
        // Current values: light 0xFFFFFF on 0x5C7A4F = 4.83:1;
        // dark 0x1E2024 on 0x9BB87E = 7.42:1.
        #expect(light >= 4.5, "light-mode on-accent ink fell below WCAG AA: \(light)")
        #expect(dark >= 4.5, "dark-mode on-accent ink fell below WCAG AA: \(dark)")
    }
}

// MARK: - Difficulty-tint on-tint-ink contract (#806)

/// Guards `SurfaceTokens.onTintInk(for:)` (GameShellUI/Theme.swift): the
/// practice-hub CTA's ink for EACH difficulty tint, in BOTH modes, must clear
/// WCAG AA (≥ 4.5:1). #797's `surface.primary`-as-ink shortcut couldn't fix
/// this class — `surface.primary` is white in light mode, which still failed
/// AA against the medium (3.19:1) and hard (2.08:1) light-ramp tints (#806).
/// This calls the PRODUCTION `onTintInkHex(for:)` picker directly (not just a
/// hand-copied expected value), so a future palette or picker-logic
/// regression fails here.
@Suite("DefaultTheme — difficulty-tint on-tint-ink contrast (#806)")
struct DifficultyTintOnTintInkContrastTests {

    private func linearize(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    private func relativeLuminance(_ hex: UInt32) -> Double {
        let red = linearize(Double((hex >> 16) & 0xFF) / 255)
        let green = linearize(Double((hex >> 8) & 0xFF) / 255)
        let blue = linearize(Double(hex & 0xFF) / 255)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    private func contrastRatio(_ first: UInt32, _ second: UInt32) -> Double {
        let lumA = relativeLuminance(first)
        let lumB = relativeLuminance(second)
        return (max(lumA, lumB) + 0.05) / (min(lumA, lumB) + 0.05)
    }

    private func assertClearsAA(name: String, tint: ThemeColor) {
        let theme = DefaultTheme()
        let ink = theme.surface.onTintInkHex(for: tint)

        let light = contrastRatio(ink.light, tint.lightHex)
        let dark = contrastRatio(ink.dark, tint.darkHex)

        #expect(light >= 4.5, "\(name) light-mode on-tint ink fell below WCAG AA: \(light)")
        #expect(dark >= 4.5, "\(name) dark-mode on-tint ink fell below WCAG AA: \(dark)")
    }

    @Test func easyOnTintInkClearsAAInBothModes() {
        assertClearsAA(name: "easy", tint: DefaultTheme().difficulty.easy)
    }

    @Test func mediumOnTintInkClearsAAInBothModes() {
        // #806: was white-on-3.19:1 (FAIL) in light mode before this fix.
        assertClearsAA(name: "medium", tint: DefaultTheme().difficulty.medium)
    }

    @Test func hardOnTintInkClearsAAInBothModes() {
        // #806: was white-on-2.08:1 (FAIL) in light mode before this fix.
        assertClearsAA(name: "hard", tint: DefaultTheme().difficulty.hard)
    }

    @Test func darkModeRatiosUnchangedByOnTintInkFix() {
        // #797 already had dark mode passing via plain `surface.primary`;
        // this proves the #806 mechanism didn't regress any of those ratios.
        let theme = DefaultTheme()
        let expectedDark: [(ThemeColor, Double)] = [
            (theme.difficulty.easy, 7.42),
            (theme.difficulty.medium, 6.89),
            (theme.difficulty.hard, 9.72),
        ]
        for (tint, expected) in expectedDark {
            let ink = theme.surface.onTintInkHex(for: tint)
            let ratio = contrastRatio(ink.dark, tint.darkHex)
            #expect(abs(ratio - expected) < 0.01, "dark ratio drifted: got \(ratio), expected ~\(expected)")
        }
    }
}
