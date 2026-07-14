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
