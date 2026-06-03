// Theme — game-agnostic design-system token machinery.
//
// Extracted into GameShellUI (#278 Tier-1 Phase 1, 2026-06-03) so every
// game's Kit shares the same theming contract. This file owns the GENERIC
// machinery only: the `Theme` protocol, the token value bundles, the
// `Color` hex/light-dark helpers, and the `@Environment(\.theme)` key.
// Each app ships its OWN concrete palette conforming to `Theme` (Sudoku's
// `DefaultTheme` stays in SudokuUI; Minesweeper adds its own in Phase 2).
//
// Per docs/designs/design-system.md §Theming. Views consume tokens via
// `@Environment(\.theme)`. A `Theme` exposes `ThemeColor` pairs (light,
// dark) for every visual token; concrete SwiftUI `Color` resolution happens
// at the call site via `Color(light:dark:)`.
//
// All tokens are `Sendable` for cross-actor passing.

public import SwiftUI

public protocol Theme: Sendable {
    var surface: SurfaceTokens { get }
    var text: TextTokens { get }
    var accent: AccentTokens { get }
    var status: StatusTokens { get }
    var difficulty: DifficultyTokens { get }
    var spacing: SpacingTokens { get }
}

// MARK: - Color pair

/// A light/dark color pair. Resolved into a SwiftUI `Color` via
/// `Color(light:dark:)`; tests can read either component directly.
public struct ThemeColor: Sendable, Equatable, Hashable {
    public let lightHex: UInt32
    public let darkHex: UInt32

    public init(light: UInt32, dark: UInt32) {
        self.lightHex = light
        self.darkHex = dark
    }

    public var light: Color { Color(hex: lightHex) }
    public var dark: Color { Color(hex: darkHex) }

    /// The SwiftUI `Color` that auto-resolves per `colorScheme`.
    public var resolved: Color { Color(light: light, dark: dark) }
}

// MARK: - Token bundles

public struct SurfaceTokens: Sendable, Equatable, Hashable {
    public let background: ThemeColor
    public let primary: ThemeColor
    public let elevated: ThemeColor
    public let placeholder: ThemeColor

    public init(
        background: ThemeColor,
        primary: ThemeColor,
        elevated: ThemeColor,
        placeholder: ThemeColor
    ) {
        self.background = background
        self.primary = primary
        self.elevated = elevated
        self.placeholder = placeholder
    }
}

public struct TextTokens: Sendable, Equatable, Hashable {
    public let primary: ThemeColor
    public let secondary: ThemeColor
    public let tertiary: ThemeColor
    public let given: ThemeColor
    public let user: ThemeColor
    public let errorDigit: ThemeColor

    public init(
        primary: ThemeColor,
        secondary: ThemeColor,
        tertiary: ThemeColor,
        given: ThemeColor,
        user: ThemeColor,
        errorDigit: ThemeColor
    ) {
        self.primary = primary
        self.secondary = secondary
        self.tertiary = tertiary
        self.given = given
        self.user = user
        self.errorDigit = errorDigit
    }
}

public struct AccentTokens: Sendable, Equatable, Hashable {
    public let primary: ThemeColor
    public let muted: ThemeColor

    public init(primary: ThemeColor, muted: ThemeColor) {
        self.primary = primary
        self.muted = muted
    }
}

public struct StatusTokens: Sendable, Equatable, Hashable {
    public let success: ThemeColor
    public let warning: ThemeColor
    public let error: ThemeColor

    public init(success: ThemeColor, warning: ThemeColor, error: ThemeColor) {
        self.success = success
        self.warning = warning
        self.error = error
    }
}

/// Difficulty signaling tokens (v2+) — design-system.md §Difficulty.
/// Restricted to difficulty signaling only (Daily card tints, Practice
/// Picker chip tints); not for general accent / CTA use.
public struct DifficultyTokens: Sendable, Equatable, Hashable {
    public let easy: ThemeColor
    public let medium: ThemeColor
    public let hard: ThemeColor

    public init(easy: ThemeColor, medium: ThemeColor, hard: ThemeColor) {
        self.easy = easy
        self.medium = medium
        self.hard = hard
    }
}

/// Base spacing scale (4 pt grid) — design-system.md §Spacing scale.
/// Production code wraps these literals in `@ScaledMetric`; this struct
/// just exposes the canonical unscaled values.
public struct SpacingTokens: Sendable, Equatable, Hashable {
    public let extraSmall: CGFloat
    public let small: CGFloat
    public let medium: CGFloat
    public let large: CGFloat
    public let extraLarge: CGFloat

    public init(
        extraSmall: CGFloat = 4,
        small: CGFloat = 8,
        medium: CGFloat = 16,
        large: CGFloat = 24,
        extraLarge: CGFloat = 32
    ) {
        self.extraSmall = extraSmall
        self.small = small
        self.medium = medium
        self.large = large
        self.extraLarge = extraLarge
    }
}

// MARK: - Color hex helper

extension Color {
    /// Build a `Color` from a 0xRRGGBB sRGB integer.
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self = Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    /// Build a color-scheme-resolving `Color` from a light/dark pair.
    init(light: Color, dark: Color) {
        self = Color(
            uiOrAppKitLight: light,
            uiOrAppKitDark: dark
        )
    }
}

// MARK: - Platform glue

#if canImport(UIKit)
import UIKit

private extension Color {
    init(uiOrAppKitLight light: Color, uiOrAppKitDark dark: Color) {
        let resolved = UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        }
        self = Color(resolved)
    }
}
#elseif canImport(AppKit)
import AppKit

private extension Color {
    init(uiOrAppKitLight light: Color, uiOrAppKitDark dark: Color) {
        let resolved = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor(dark) : NSColor(light)
        }
        self = Color(nsColor: resolved)
    }
}
#endif

// MARK: - Neutral fallback theme

/// A palette-neutral `Theme` used only as the `@Environment(\.theme)`
/// default value. GameShellUI cannot know any specific app's palette, so
/// this deliberately ships grayscale / system-derived placeholders — NOT
/// any app's brand colors. Every app injects its own concrete theme at its
/// root (`.environment(\.theme, ...)`); this fallback exists purely so the
/// environment key is well-formed and previews of un-injected subtrees
/// render something legible rather than crashing.
public struct NeutralTheme: Theme {
    public init() {}

    public let surface = SurfaceTokens(
        background: ThemeColor(light: 0xF2F2F2, dark: 0x1C1C1E),
        primary: ThemeColor(light: 0xFFFFFF, dark: 0x2C2C2E),
        elevated: ThemeColor(light: 0xFFFFFF, dark: 0x3A3A3C),
        placeholder: ThemeColor(light: 0xE5E5EA, dark: 0x2C2C2E)
    )

    public let text = TextTokens(
        primary: ThemeColor(light: 0x1C1C1E, dark: 0xF2F2F7),
        secondary: ThemeColor(light: 0x636366, dark: 0xAEAEB2),
        tertiary: ThemeColor(light: 0x8E8E93, dark: 0x7C7C80),
        given: ThemeColor(light: 0x1C1C1E, dark: 0xF2F2F7),
        user: ThemeColor(light: 0x636366, dark: 0xAEAEB2),
        errorDigit: ThemeColor(light: 0xD0021B, dark: 0xFF453A)
    )

    public let accent = AccentTokens(
        primary: ThemeColor(light: 0x636366, dark: 0xAEAEB2),
        muted: ThemeColor(light: 0xD1D1D6, dark: 0x48484A)
    )

    public let status = StatusTokens(
        success: ThemeColor(light: 0x34C759, dark: 0x30D158),
        warning: ThemeColor(light: 0xFF9500, dark: 0xFF9F0A),
        error: ThemeColor(light: 0xD0021B, dark: 0xFF453A)
    )

    public let difficulty = DifficultyTokens(
        easy: ThemeColor(light: 0x8E8E93, dark: 0xAEAEB2),
        medium: ThemeColor(light: 0x636366, dark: 0x8E8E93),
        hard: ThemeColor(light: 0x48484A, dark: 0x636366)
    )

    public let spacing = SpacingTokens()
}

// MARK: - Environment key

private struct ThemeKey: EnvironmentKey {
    // Palette-neutral default. Apps MUST inject their own concrete theme at
    // their root; this fallback never carries app brand colors.
    static let defaultValue: any Theme = NeutralTheme()
}

public extension EnvironmentValues {
    var theme: any Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
