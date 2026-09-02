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
    /// #1021 Phase B (additive): indices into `last7` whose pip is a
    /// completed, reviewable PAST day — mirrors the per-app `DailyStripView.
    /// isTappable` gate (`isReviewable && !isToday`) the retired week-strip
    /// card used to apply per-dot. Empty by default so every existing Phase A
    /// call site keeps compiling unchanged; a caller that wants tap-to-review
    /// pips computes this set itself (this view has no notion of "day" beyond
    /// a plain `Bool`, so it can't derive tappability on its own).
    public let tappablePipIndices: Set<Int>
    /// #1021 Phase B (additive): per-pip VoiceOver label, read only for an
    /// index also present in `tappablePipIndices` (mirrors the retired
    /// `DailyStripView.accessibilityLabel(for:)` — e.g. "Monday, completed").
    /// A tappable index with no entry here (index out of bounds) falls back
    /// to an empty label rather than trapping. Non-tappable pips stay
    /// `.accessibilityHidden` — the header's own combined label above already
    /// speaks `current`/`longest`.
    public let pipAccessibilityLabels: [String]

    public init(
        current: Int,
        longest: Int?,
        last7: [Bool],
        isSkeleton: Bool,
        tappablePipIndices: Set<Int> = [],
        pipAccessibilityLabels: [String] = []
    ) {
        self.current = current
        self.longest = longest
        self.last7 = last7
        self.isSkeleton = isSkeleton
        self.tappablePipIndices = tappablePipIndices
        self.pipAccessibilityLabels = pipAccessibilityLabels
    }
}

public struct StreakHeaderView: View {
    @Environment(\.theme) private var theme
    @ScaledSpacing(.small) private var contentGap

    private let model: StreakHeaderModel
    /// #1021 Phase B (additive): fired with the tapped pip's `last7` index
    /// when that index is in `model.tappablePipIndices`. `nil` (default)
    /// keeps every pip inert, matching Phase A's original behavior.
    private let onPipTap: ((Int) -> Void)?

    private static let pipDiameter: CGFloat = 10
    private static let pipGap: CGFloat = 6

    public init(model: StreakHeaderModel, onPipTap: ((Int) -> Void)? = nil) {
        self.model = model
        self.onPipTap = onPipTap
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
        // #1021 Phase B: `.contain` (was `.ignore`) so a tappable pip's own
        // Button surfaces to VoiceOver as a real, navigable element — `.ignore`
        // would silently swallow every descendant, including the pip buttons
        // added below, making the streak's completed-past-day review
        // unreachable without sight. With no tappable pips (every pip
        // `.accessibilityHidden`, see `pipRow`) this behaves identically to
        // the old `.ignore`: no descendants surface either way.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Self.accessibilityLabel(current: model.current, longest: model.longest))
    }

    private var pipRow: some View {
        HStack(spacing: Self.pipGap) {
            ForEach(Array(model.last7.enumerated()), id: \.offset) { index, filled in
                let isToday = index == model.last7.count - 1
                if let onPipTap, model.tappablePipIndices.contains(index) {
                    Button {
                        onPipTap(index)
                    } label: {
                        pip(filled: filled, isToday: isToday)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(pipAccessibilityLabel(at: index))
                    .accessibilityHint(Self.reviewHint)
                    .accessibilityAddTraits(.isButton)
                } else {
                    // Decorative — the header's own combined label above
                    // already speaks `current`/`longest`; an inert pip has no
                    // additional per-day fact worth a VoiceOver stop.
                    pip(filled: filled, isToday: isToday)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func pipAccessibilityLabel(at index: Int) -> String {
        model.pipAccessibilityLabels.indices.contains(index) ? model.pipAccessibilityLabels[index] : ""
    }

    private static let reviewHint = String(localized: "View this day's result", bundle: .main)

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
