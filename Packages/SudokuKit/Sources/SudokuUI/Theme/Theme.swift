// Theme — design-system token bundle.
//
// Per design.md §How.5.4 and docs/designs/design-system.md §Theming.
// Views consume tokens via `@Environment(\.theme)`. A `Theme` exposes
// `ThemeColor` pairs (light, dark) for every visual token; concrete SwiftUI
// `Color` resolution happens at the call site via `Color(light:dark:)`.
//
// All tokens are `Sendable` for cross-actor passing.

public import SwiftUI

public protocol Theme: Sendable {
    var surface: SurfaceTokens { get }
    var cell: CellTokens { get }
    var text: TextTokens { get }
    var accent: AccentTokens { get }
    var status: StatusTokens { get }
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

public struct CellTokens: Sendable, Equatable, Hashable {
    public let base: ThemeColor
    public let prefilled: ThemeColor
    public let userFilled: ThemeColor
    public let highlighted: ThemeColor
    public let selected: ThemeColor
    public let error: ThemeColor
    public let errorBorder: ThemeColor

    public init(
        base: ThemeColor,
        prefilled: ThemeColor,
        userFilled: ThemeColor,
        highlighted: ThemeColor,
        selected: ThemeColor,
        error: ThemeColor,
        errorBorder: ThemeColor
    ) {
        self.base = base
        self.prefilled = prefilled
        self.userFilled = userFilled
        self.highlighted = highlighted
        self.selected = selected
        self.error = error
        self.errorBorder = errorBorder
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

// MARK: - Environment key

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: any Theme = DefaultTheme()
}

public extension EnvironmentValues {
    var theme: any Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
