// StreakHeaderView — TODAY's streak line (#1021 Phase A, design.md §3.1 /
// §4.2: "Streak 一列...內容層普通文字,不用玻璃不用卡片"). Plain content-layer
// text, deliberately NOT wrapped in `HubCard` — §4.2 explains why: this row
// carries no transient interaction, so it never qualifies for the
// Slider/Toggle glass exception, and content-layer elements outside that
// exception use standard materials or, as here, no container at all.

public import SwiftUI

public struct StreakHeaderModel: Sendable, Equatable {
    public let current: Int
    public let longest: Int?
    /// Oldest → newest, ending today. `count` need not be exactly 7 — callers
    /// with a shorter history pass a shorter array.
    public let last7: [Bool]
    public let isSkeleton: Bool

    public init(current: Int, longest: Int?, last7: [Bool], isSkeleton: Bool) {
        self.current = current
        self.longest = longest
        self.last7 = last7
        self.isSkeleton = isSkeleton
    }
}

public struct StreakHeaderView: View {
    @Environment(\.theme) private var theme
    @ScaledSpacing(.small) private var contentGap

    private let model: StreakHeaderModel

    private static let pipDiameter: CGFloat = 10
    private static let pipGap: CGFloat = 6

    public init(model: StreakHeaderModel) {
        self.model = model
    }

    public var body: some View {
        HStack(alignment: .center, spacing: contentGap) {
            VStack(alignment: .leading, spacing: contentGap) {
                Text(Self.streakTitle(current: model.current))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(theme.text.primary.resolved)
                pipRow
            }
            Spacer(minLength: contentGap)
            if let longest = model.longest {
                Text(Self.bestCaption(longest: longest))
                    .font(.subheadline)
                    .foregroundStyle(theme.text.secondary.resolved)
            }
        }
        .redacted(reason: model.isSkeleton ? .placeholder : [])
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(current: model.current, longest: model.longest))
    }

    private var pipRow: some View {
        HStack(spacing: Self.pipGap) {
            ForEach(Array(model.last7.enumerated()), id: \.offset) { index, filled in
                let isToday = index == model.last7.count - 1
                pip(filled: filled, isToday: isToday)
            }
        }
        .accessibilityHidden(true)
    }

    private func pip(filled: Bool, isToday: Bool) -> some View {
        Circle()
            .fill(filled ? theme.accent.primary.resolved : theme.streak.pipOff.resolved)
            .overlay(
                Circle().strokeBorder(isToday ? theme.accent.primary.resolved : Color.clear, lineWidth: 1.5)
            )
            .frame(width: Self.pipDiameter, height: Self.pipDiameter)
    }

    private static func streakTitle(current: Int) -> String {
        String(localized: "\(current) day streak", bundle: .main)
    }

    private static func bestCaption(longest: Int) -> String {
        String(localized: "Best \(longest)", bundle: .main)
    }

    public static func accessibilityLabel(current: Int, longest: Int?) -> String {
        guard let longest else {
            return streakTitle(current: current)
        }
        return String(localized: "\(current) day streak, best \(longest)", bundle: .main)
    }
}
