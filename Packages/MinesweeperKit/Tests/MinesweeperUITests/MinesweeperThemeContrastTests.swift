// MinesweeperThemeContrastTests — on-accent-ink contract guard (#786/#797).
//
// Mirrors SudokuKit's `DefaultThemeOnAccentContrastTests` (ThemeTests.swift):
// `SurfaceTokens.primary` is the canonical ink for prominent accent-filled
// controls (see its doc in GameShellUI/Theme.swift), so it must clear WCAG AA
// (≥ 4.5:1) against `accent.primary` in both modes. A future MS palette tweak
// (or a new game copying this file, per the contract doc) that drops below AA
// fails here instead of shipping — the exact defect class #786/#797 fixed by
// hand. Luminance math is the standard WCAG 2.x relative-luminance formula,
// inlined per the #797 CR instruction (no new shared test target).

import Foundation
import GameShellUI
import Testing
@testable import MinesweeperUI

@Suite("MinesweeperTheme — on-accent ink contrast (#797)")
struct MinesweeperThemeContrastTests {

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
        let theme = MinesweeperTheme()
        let light = contrastRatio(theme.surface.primary.lightHex, theme.accent.primary.lightHex)
        let dark = contrastRatio(theme.surface.primary.darkHex, theme.accent.primary.darkHex)
        // Current values: light 0xFFFFFF on 0x3E6B8C = 5.70:1;
        // dark 0x1C2026 on 0x7FAFCF = 6.96:1.
        #expect(light >= 4.5, "light-mode on-accent ink fell below WCAG AA: \(light)")
        #expect(dark >= 4.5, "dark-mode on-accent ink fell below WCAG AA: \(dark)")
    }
}

// MARK: - Difficulty-tint on-tint-ink contract (#806)

/// Mirrors SudokuKit's `DifficultyTintOnTintInkContrastTests`. Guards
/// `SurfaceTokens.onTintInk(for:)` (GameShellUI/Theme.swift): the practice-hub
/// CTA's ink for EACH difficulty tint (Beginner/Intermediate/Expert), in BOTH
/// modes, must clear WCAG AA (≥ 4.5:1). #797's `surface.primary`-as-ink
/// shortcut couldn't fix this class — `surface.primary` is white in light
/// mode, which still failed AA against the Intermediate light-ramp tint
/// (3.19:1, #806). Calls the PRODUCTION `onTintInkHex(for:)` picker directly.
@Suite("MinesweeperTheme — difficulty-tint on-tint-ink contrast (#806)")
struct MinesweeperDifficultyTintOnTintInkContrastTests {

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
        let theme = MinesweeperTheme()
        let ink = theme.surface.onTintInkHex(for: tint)

        let light = contrastRatio(ink.light, tint.lightHex)
        let dark = contrastRatio(ink.dark, tint.darkHex)

        #expect(light >= 4.5, "\(name) light-mode on-tint ink fell below WCAG AA: \(light)")
        #expect(dark >= 4.5, "\(name) dark-mode on-tint ink fell below WCAG AA: \(dark)")
    }

    @Test func beginnerOnTintInkClearsAAInBothModes() {
        assertClearsAA(name: "beginner", tint: MinesweeperTheme().difficulty.easy)
    }

    @Test func intermediateOnTintInkClearsAAInBothModes() {
        // #806: was white-on-3.19:1 (FAIL) in light mode before this fix.
        assertClearsAA(name: "intermediate", tint: MinesweeperTheme().difficulty.medium)
    }

    @Test func expertOnTintInkClearsAAInBothModes() {
        assertClearsAA(name: "expert", tint: MinesweeperTheme().difficulty.hard)
    }

    @Test func darkModeRatiosUnchangedByOnTintInkFix() {
        // #797 already had dark mode passing via plain `surface.primary`;
        // this proves the #806 mechanism didn't regress any of those ratios.
        let theme = MinesweeperTheme()
        let expectedDark: [(ThemeColor, Double)] = [
            (theme.difficulty.easy, 6.96),
            (theme.difficulty.medium, 6.90),
            (theme.difficulty.hard, 4.92),
        ]
        for (tint, expected) in expectedDark {
            let ink = theme.surface.onTintInkHex(for: tint)
            let ratio = contrastRatio(ink.dark, tint.darkHex)
            #expect(abs(ratio - expected) < 0.01, "dark ratio drifted: got \(ratio), expected ~\(expected)")
        }
    }
}

// MARK: - Lost-mine flag ink non-text contrast (#876 / #874 F-1)

/// Guards `MinesweeperCellTokens.lostMineFlagInk` against the `mine` fill it
/// renders on (`MinesweeperCellButton.flaggedMineGlyph` —
/// `showsLostMine && cell.state == .flagged`). This is a graphical-object
/// (icon), not text, so the WCAG floor is 1.4.11's 3:1, not the 4.5:1 AA text
/// threshold the other suites in this file check. Before this fix, the
/// general `status.warning` flag ink measured 2.39:1 light / 6.22:1 dark
/// against `mine` — light failed the 3:1 floor.
@Suite("MinesweeperTheme — lost-mine flag ink contrast (#876)")
struct MinesweeperLostMineFlagInkContrastTests {

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

    @Test func lostMineFlagInkClearsNonTextFloorInBothModes() {
        let tokens = MinesweeperTheme().cell
        let light = contrastRatio(tokens.lostMineFlagInk.lightHex, tokens.mine.lightHex)
        let dark = contrastRatio(tokens.lostMineFlagInk.darkHex, tokens.mine.darkHex)
        // Current values: light 0x9C5C1C on 0xFBE3E1 = 4.34:1;
        // dark 0xE8A560 on 0x4A2724 = 6.22:1 (dark ink is `status.warning`'s
        // dark value, reused verbatim — unchanged by this fix).
        #expect(light >= 3.0, "light-mode lost-mine flag ink fell below WCAG 1.4.11: \(light)")
        #expect(dark >= 3.0, "dark-mode lost-mine flag ink fell below WCAG 1.4.11: \(dark)")
    }

    @Test func darkModeRatioUnchangedFromStatusWarning() {
        // #876 reuses `status.warning`'s dark hex verbatim for the dark ink,
        // so this proves the dark-mode ratio is byte-identical pre/post-fix.
        let theme = MinesweeperTheme()
        let dark = contrastRatio(theme.cell.lostMineFlagInk.darkHex, theme.cell.mine.darkHex)
        #expect(abs(dark - 6.22) < 0.01, "dark ratio drifted: got \(dark), expected ~6.22")
    }
}
