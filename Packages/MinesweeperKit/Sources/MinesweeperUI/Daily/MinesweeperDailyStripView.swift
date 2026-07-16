// MinesweeperDailyStripView — the rolling 7-day completion strip + streak
// caption. Mirrors `SudokuUI.DailyStripView` (copy-paste-adapt per the
// proposal's scope note — see that file's header comment for the full
// interaction-scope rationale, not repeated here).
//
// Interaction scope (#826, owner adjudication 2026-07-16): a COMPLETED PAST
// day's dot is a button — tap opens that day's Completion review (exactly one
// completed difficulty → direct open; more than one → a confirmationDialog
// picker, hosted by `MinesweeperDailyHubView`). Today's dot and any
// missed/empty day stay inert. Mirrors `SudokuUI.DailyStripView` — see that
// file's header comment for the 44pt-tap-target-via-contentShape rationale
// (not repeated here).

import SwiftUI
internal import GameShellUI

struct MinesweeperDailyStripView: View {
    let snapshot: MinesweeperDailyStripSnapshot
    /// #826: fired only for a tappable dot (`isTappable(_:)` == true).
    var onDayTap: (MinesweeperDailyStripDay) -> Void = { _ in }
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledSpacing(.small) private var captionGap
    private let dotDiameter: CGFloat = 16
    private let dotGap: CGFloat = 8
    private let tapTargetDiameter: CGFloat = 44

    /// #826: mirrors `SudokuUI.DailyStripView.isTappable` — keyed on
    /// `isReviewable` (≥1 parseable completed id), not raw `isCompleted`, so
    /// a malformed-ids day never grows a button/trait/hint whose tap would
    /// no-op (CR round 2); see the Sudoku doc for the full rationale.
    func isTappable(_ day: MinesweeperDailyStripDay) -> Bool {
        day.isReviewable && !day.isToday
    }

    var body: some View {
        VStack(alignment: .leading, spacing: captionGap) {
            HStack(spacing: dotGap) {
                if snapshot.days.isEmpty {
                    ForEach(0..<7, id: \.self) { _ in placeholderDot }
                } else {
                    ForEach(snapshot.days) { day in dotView(for: day) }
                }
            }
            .accessibilityElement(children: snapshot.days.isEmpty ? .ignore : .contain)
            .accessibilityHidden(snapshot.days.isEmpty)
            if let streak = snapshot.streak {
                // Two keys instead of one interpolated "%@ day streak" — see
                // `SudokuUI.DailyStripView` for the plural-agreement
                // rationale. 7 == the fetch window size (streak saturates
                // there).
                Group {
                    if streak >= 7 {
                        Text("7+ day streak")
                    } else {
                        Text("\(streak) day streak")
                    }
                }
                .font(.caption)
                .foregroundStyle(theme.text.secondary.resolved)
            }
        }
        // Align the strip with the trio cards' leading screen-edge inset —
        // without this the VStack shrinks to content and gets centered.
        // Mirrors `SudokuUI.DailyStripView`.
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: snapshot)
    }

    private var placeholderDot: some View {
        Circle()
            .strokeBorder(theme.text.tertiary.resolved.opacity(0.3), lineWidth: 1)
            .frame(width: dotDiameter, height: dotDiameter)
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
                Circle().fill(theme.accent.primary.resolved)
            } else if day.isToday {
                Circle().strokeBorder(theme.accent.primary.resolved, lineWidth: 1.5)
            } else {
                Circle().strokeBorder(theme.text.tertiary.resolved.opacity(0.3), lineWidth: 1)
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
}
