// BoardControlRail — #1114, shared by both games.
//
// The regular-width (iPad + Mac) control rail's width is ONE number read by
// every game; two private 260s is the cross-app drift the mirror principle
// forbids. A key grid on the rail derives its key size from that number so the
// grid can never overhang the rail.
public import CoreGraphics

/// Geometry of the regular-width control rail, shared by every game.
public enum BoardControlRail {
    /// The regular-width control rail's width, shared by every game.
    public static let width: CGFloat = 260

    /// Spacing between keys in a key grid on the rail.
    public static let keyGridSpacing: CGFloat = 8

    /// Horizontal padding the system glass button style adds on each side of a
    /// label, at its widest.
    ///
    /// A measured platform fact, not derived: measured 2026-11-14 on iPadOS 26.5
    /// (iPad Pro 11-inch (M5) simulator), where a label with `minWidth: 64`
    /// rendered an 88 pt key. macOS adds about 5 pt per side. Re-measure if a
    /// new OS changes the glass button metrics.
    public static let widestButtonChromeInset: CGFloat = 12

    /// Width of one key, chrome included, for a grid of `columns` filling the rail.
    public static func keyWidth(columns: Int) -> CGFloat {
        (width - CGFloat(columns - 1) * keyGridSpacing) / CGFloat(columns)
    }

    /// Minimum label width that keeps `columns` keys inside the rail even with
    /// the widest button chrome. Rounded down so floating-point error can never
    /// push the minimum keys plus spacing past the rail.
    public static func keyLabelMinWidth(columns: Int) -> CGFloat {
        (keyWidth(columns: columns) - 2 * widestButtonChromeInset).rounded(.down)
    }
}
