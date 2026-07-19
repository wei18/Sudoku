// MinesweeperDailyStripView — the rolling 7-day completion strip + streak
// caption, rendered as a card-contained calendar strip (#843 redesign,
// Option A). Mirrors `SudokuUI.DailyStripView` (copy-paste-adapt per the
// proposal's scope note — see that file's header comment for the full
// interaction-scope + card-anatomy + degrade rationale, not repeated here).
//
// Interaction scope (#826, owner adjudication 2026-07-16): a COMPLETED PAST
// day's dot is a button — tap opens that day's Completion review (exactly one
// completed difficulty → direct open; more than one → a confirmationDialog
// picker, hosted by `MinesweeperDailyHubView`). Today's dot and any
// missed/empty day stay inert. Mirrors `SudokuUI.DailyStripView` — see that
// file's header comment for the 44pt-tap-target-via-contentShape rationale
// (not repeated here).
//
// #882 F-3: the missed dot's solid outline now carries an additional xmark
// overlay (full-strength `text.tertiary` ink, WCAG 1.4.11 ≥3.36:1 against
// `surface.elevated` in both schemes) — see `SudokuUI.DailyStripView`'s
// "Dot states" comment for the full rationale, not repeated here.

import SwiftUI
internal import GameShellUI

struct MinesweeperDailyStripView: View {
    let snapshot: MinesweeperDailyStripSnapshot
    /// #826: fired only for a tappable dot (`isTappable(_:)` == true).
    var onDayTap: (MinesweeperDailyStripDay) -> Void = { _ in }
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ScaledSpacing(.small) private var headerToDotGap
    @ScaledSpacing(.medium) private var cardPadding
    @ScaledSpacing(.extraSmall) private var headerIconGap

    private let dotDiameter: CGFloat = 28
    private let dotGap: CGFloat = 8
    private let dotLabelGap: CGFloat = 4
    private let cardCornerRadius: CGFloat = 16
    private let tapTargetDiameter: CGFloat = 44

    /// #826: mirrors `SudokuUI.DailyStripView.isTappable` — keyed on
    /// `isReviewable` (≥1 parseable completed id), not raw `isCompleted`, so
    /// a malformed-ids day never grows a button/trait/hint whose tap would
    /// no-op (CR round 2); see the Sudoku doc for the full rationale.
    func isTappable(_ day: MinesweeperDailyStripDay) -> Bool {
        day.isReviewable && !day.isToday
    }

    var body: some View {
        if snapshot.days.isEmpty {
            // #843: all-or-nothing degrade — the whole card is omitted from
            // layout rather than showing a subdued skeleton. Mirrors
            // `SudokuUI.DailyStripView`.
            EmptyView()
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: headerToDotGap) {
            if let streak = snapshot.streak {
                header(streak: streak)
            }
            dotRow
        }
        .padding(cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface.elevated.resolved, in: RoundedRectangle(cornerRadius: cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius)
                .strokeBorder(theme.text.tertiary.resolved.opacity(0.14), lineWidth: 1)
        )
        .animation(MotionGate.animation(.easeInOut(duration: 0.2), reduceMotion: reduceMotion), value: snapshot)
    }

    @ViewBuilder
    private func header(streak: Int) -> some View {
        HStack(spacing: headerIconGap) {
            Image(systemName: "flame.fill")
                .foregroundStyle(theme.status.warning.resolved)
                .accessibilityHidden(true)
            streakCaption(streak: streak)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(theme.text.primary.resolved)
        }
        // #843 spec: AX3 cap on the header text, mirroring
        // `CompletionOverlayScaffold`'s `.dynamicTypeSize(...accessibility2)`
        // cap. Mirrors `SudokuUI.DailyStripView`.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .combine)
    }

    /// Two keys instead of one interpolated "%@ day streak" — see
    /// `SudokuUI.DailyStripView` for the plural-agreement + spec-deviation
    /// rationale (not repeated here). Reuses the existing keys verbatim.
    private func streakCaption(streak: Int) -> Text {
        streak >= 7 ? Text("7+ day streak") : Text("\(streak) day streak")
    }

    private var dotRow: some View {
        HStack(spacing: dotGap) {
            ForEach(snapshot.days) { day in dayColumn(for: day) }
        }
        .accessibilityElement(children: .contain)
    }

    private func dayColumn(for day: MinesweeperDailyStripDay) -> some View {
        VStack(spacing: dotLabelGap) {
            dotView(for: day)
            Text(weekdayInitial(for: day.date))
                .font(.caption2)
                .foregroundStyle(theme.text.tertiary.resolved)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func dotView(for day: MinesweeperDailyStripDay) -> some View {
        if isTappable(day) {
            Button {
                onDayTap(day)
            } label: {
                dotShape(for: day)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle().inset(by: -(tapTargetDiameter - dotDiameter) / 2))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(for: day))
            .accessibilityHint(reviewHint)
            .accessibilityAddTraits(.isButton)
        } else {
            dotShape(for: day)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(for: day))
        }
    }

    @ViewBuilder
    private func dotShape(for day: MinesweeperDailyStripDay) -> some View {
        Group {
            if day.isCompleted {
                Circle()
                    .fill(theme.accent.primary.resolved)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: dotDiameter * 0.5, weight: .bold))
                            .foregroundStyle(theme.surface.onTintInk(for: theme.accent.primary))
                    }
            } else if day.isToday {
                Circle()
                    .strokeBorder(theme.accent.primary.resolved, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            } else {
                // #882 F-3: mirrors `SudokuUI.DailyStripView` — see that
                // file's "Dot states" comment for the contrast math.
                Circle()
                    .strokeBorder(theme.text.tertiary.resolved.opacity(0.4), lineWidth: 1)
                    .overlay {
                        Image(systemName: "xmark")
                            .font(.system(size: dotDiameter * 0.32, weight: .semibold))
                            .foregroundStyle(theme.text.tertiary.resolved)
                    }
            }
        }
        .frame(width: dotDiameter, height: dotDiameter)
    }

    private var reviewHint: String {
        String(localized: "View this day's result", bundle: .main)
    }

    private func accessibilityLabel(for day: MinesweeperDailyStripDay) -> String {
        let weekday = day.date.formatted(.dateTime.weekday(.wide))
        if day.isToday {
            return day.isCompleted
                ? String(localized: "\(weekday), today, completed", bundle: .main)
                : String(localized: "\(weekday), today, not yet completed", bundle: .main)
        }
        return day.isCompleted
            ? String(localized: "\(weekday), completed", bundle: .main)
            : String(localized: "\(weekday), missed", bundle: .main)
    }

    /// Locale-correct weekday initial, sourced from
    /// `Calendar.current.veryShortWeekdaySymbols` — NOT a new translatable
    /// string. Mirrors `SudokuUI.DailyStripView.weekdayInitial(for:)`.
    private func weekdayInitial(for date: Date) -> String {
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols
        let index = calendar.component(.weekday, from: date) - 1
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index]
    }
}
