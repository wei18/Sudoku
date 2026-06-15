// Game2048TileView — single-cell renderer for the 4×4 board grid.
//
// Each cell is either empty (nil) or carries a power-of-two value.
// The tile background and text colours are value-derived using a fixed
// palette that matches the classic 2048 aesthetic.
//
// Mirrors MinesweeperCellButton's role: a leaf View receiving pre-computed
// data, no state of its own, callbacks fired by the parent board view.

internal import SwiftUI
internal import Game2048Engine

// MARK: - Tile palette
//
// Flat colours rather than adaptive pairs — classic 2048 uses a single
// warm palette that works in both schemes. The board background provides
// the dark/light context; the tile colours are game-semantic constants.

private enum TilePalette {
    struct Entry {
        let background: Color
        let text: Color
    }

    static func entry(for value: Int?) -> Entry {
        guard let value else {
            return Entry(background: Color(hex: 0xCDC1B4), text: .clear)
        }
        return Entry(background: background(for: value), text: textColor(for: value))
    }

    // Split into two smaller functions so cyclomatic complexity stays ≤ 10.
    private static func background(for value: Int) -> Color {
        switch value {
        case 2:    return Color(hex: 0xEEE4DA)
        case 4:    return Color(hex: 0xEDE0C8)
        case 8:    return Color(hex: 0xF2B179)
        case 16:   return Color(hex: 0xF59563)
        case 32:   return Color(hex: 0xF67C5F)
        case 64:   return Color(hex: 0xF65E3B)
        case 128:  return Color(hex: 0xEDCF72)
        case 256:  return Color(hex: 0xEDCC61)
        case 512:  return Color(hex: 0xEDC850)
        case 1024: return Color(hex: 0xEDC53F)
        case 2048: return Color(hex: 0xEDC22E)
        default:   return Color(hex: 0x3C3A32)
        }
    }

    private static func textColor(for value: Int) -> Color {
        value <= 4 ? Color(hex: 0x776E65) : Color(hex: 0xF9F6F2)
    }
}

// MARK: - Tile view

struct Game2048TileView: View {

    let value: Int?
    /// Side length in points, derived from the board GeometryReader.
    let side: CGFloat

    var body: some View {
        let palette = TilePalette.entry(for: value)
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(palette.background)
            if let value {
                Text(displayLabel(value))
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.text)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .padding(2)
            }
        }
        .frame(width: side, height: side)
    }

    // MARK: - Geometry

    private var cornerRadius: CGFloat { max(4, side * 0.1) }
    private var fontSize: CGFloat { side * 0.38 }

    // MARK: - Label

    /// Abbreviated label for large values so they fit the tile at any size.
    private func displayLabel(_ value: Int) -> String {
        if value >= 1_000_000 {
            return "\(value / 1_000_000)M"
        } else if value >= 1_000 {
            return "\(value / 1_000)k"
        }
        return "\(value)"
    }
}

// MARK: - Color from hex

private extension Color {
    /// Construct a Color from an 0xRRGGBB hex literal (sRGB, full opacity).
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
