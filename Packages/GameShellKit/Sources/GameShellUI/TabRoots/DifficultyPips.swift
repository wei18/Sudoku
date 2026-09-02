// DifficultyPips — pip-count redundant difficulty encoding (#1021 Phase A,
// design.md §7 "顏色非唯一通道: 難度用 pip 數量冗餘編碼").
//
// Filled pips all share ONE tint per `level` (`difficulty.easy/medium/hard`
// — a single-hue lightness ramp, design-system.md §Difficulty), never a
// rainbow across pips: the COUNT of filled pips is the primary signal, the
// tint is a secondary reinforcement of the same level, not a second
// independent code.

public import SwiftUI

public struct DifficultyPips: View {
    @Environment(\.theme) private var theme

    private let level: Int
    private let max: Int

    private static let pipDiameter: CGFloat = 6
    private static let pipGap: CGFloat = 4

    public init(level: Int, max: Int = 3) {
        self.level = level
        self.max = max
    }

    public var body: some View {
        HStack(spacing: Self.pipGap) {
            ForEach(0..<max, id: \.self) { index in
                Circle()
                    .fill(index < level ? tint : theme.surface.placeholder.resolved)
                    .frame(width: Self.pipDiameter, height: Self.pipDiameter)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(level: level, max: max))
    }

    /// `difficulty.hard` for the top tier and everything above it (a `level`
    /// past `max` still reads as "hard", it never traps or falls through).
    private var tint: Color {
        switch level {
        case ...1: theme.difficulty.easy.resolved
        case 2: theme.difficulty.medium.resolved
        default: theme.difficulty.hard.resolved
        }
    }

    public static func accessibilityLabel(level: Int, max: Int) -> String {
        String(localized: "Difficulty \(level) of \(max)", bundle: .main)
    }
}
