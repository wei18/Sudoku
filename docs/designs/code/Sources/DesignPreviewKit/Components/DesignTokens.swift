// DESIGN PREVIEW ONLY — docs/designs/code/Components/DesignTokens.swift
//
// Design-system tokens lifted from docs/designs/design-system.md.
// Standalone — no SudokuKit / SudokuEngine dependency. Snapshot-stable
// (literal hex; no @ScaledMetric — see design-system.md §Spacing note).
//
// Production code path will replace these with the `Theme` protocol shown
// in design-system.md §Theming. For preview / snapshot purposes a flat
// struct of `Color`s that resolve light/dark via SwiftUI's built-in
// `Color(light:dark:)` initializer is sufficient.

import SwiftUI

public extension Color {
    /// Resolve a color pair based on `colorScheme` at render time.
    /// SwiftUI 17+ supports an initializer that takes light/dark variants;
    /// we model it with a small wrapper so DesignTokens stays one source.
    init(light: Color, dark: Color) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #elseif canImport(AppKit)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor(dark) : NSColor(light)
        })
        #else
        self = light
        #endif
    }

    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

// MARK: - Tokens

public enum DesignTokens {

    // Surfaces
    public static let surfaceBackground = Color(light: .init(hex: 0xFAF8F3), dark: .init(hex: 0x15171A))
    public static let surfacePrimary    = Color(light: .init(hex: 0xFFFFFF), dark: .init(hex: 0x1E2024))
    public static let surfaceElevated   = Color(light: .init(hex: 0xFFFFFF), dark: .init(hex: 0x262A30))
    public static let surfacePlaceholder = Color(light: .init(hex: 0xEDEAE3), dark: .init(hex: 0x2A2D33))

    // Cells
    public static let cellBase        = Color(light: .init(hex: 0xFFFFFF), dark: .init(hex: 0x1E2024))
    public static let cellPrefilled   = Color(light: .init(hex: 0xEFEBE2), dark: .init(hex: 0x2A2D33))
    public static let cellHighlighted = Color(light: .init(hex: 0xEBF0E2), dark: .init(hex: 0x252D1F))
    public static let cellSelected    = Color(light: .init(hex: 0xDCE6D0), dark: .init(hex: 0x3A4A30))
    public static let cellError       = Color(light: .init(hex: 0xFBE3E1), dark: .init(hex: 0x4A2724))
    public static let cellErrorBorder = Color(light: .init(hex: 0xC8362B), dark: .init(hex: 0xE66258))

    // Text
    public static let textPrimary    = Color(light: .init(hex: 0x1A1D21), dark: .init(hex: 0xF2F3F5))
    public static let textSecondary  = Color(light: .init(hex: 0x54595F), dark: .init(hex: 0xA8ADB3))
    public static let textTertiary   = Color(light: .init(hex: 0x86898E), dark: .init(hex: 0x787C82))
    public static let textGiven      = Color(light: .init(hex: 0x1A1D21), dark: .init(hex: 0xF2F3F5))
    public static let textUser       = Color(light: .init(hex: 0x5C7A4F), dark: .init(hex: 0x9BB87E))
    public static let textErrorDigit = Color(light: .init(hex: 0xA52A20), dark: .init(hex: 0xFF8077))

    // Accent
    public static let accentPrimary = Color(light: .init(hex: 0x5C7A4F), dark: .init(hex: 0x9BB87E))
    public static let accentMuted   = Color(light: .init(hex: 0xDCE6D0), dark: .init(hex: 0x3A4A30))

    // Status
    public static let statusSuccess = Color(light: .init(hex: 0x1B7A3E), dark: .init(hex: 0x4BC579))
    public static let statusWarning = Color(light: .init(hex: 0xA86A0E), dark: .init(hex: 0xE0A95C))
    public static let statusError   = Color(light: .init(hex: 0xC8362B), dark: .init(hex: 0xE66258))

    // Spacing — base 4
    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
    }

    // Corner radii
    public enum Radius {
        public static let card: CGFloat = 16
        public static let pill: CGFloat = 14
        public static let chip: CGFloat = 12
        public static let row: CGFloat = 8
    }
}
