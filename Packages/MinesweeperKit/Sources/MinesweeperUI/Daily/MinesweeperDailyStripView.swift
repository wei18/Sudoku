// MinesweeperDailyStripView — the rolling 7-day completion strip + streak
// caption. Mirrors `SudokuUI.DailyStripView` (copy-paste-adapt per the
// proposal's scope note — see that file's header comment for the full
// interaction-scope rationale, not repeated here).
//
// Interaction scope: VIEW-ONLY in v1 — no dot is tappable. MS's
// `.completion(difficulty:mode:)` route carries no date/seed, so it cannot
// resolve to a specific PAST day's review without a route signature change
// (out of scope for this dispatch — flagged to the owner/Leader).

import SwiftUI
internal import GameShellUI

struct MinesweeperDailyStripView: View {
    let snapshot: MinesweeperDailyStripSnapshot
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledSpacing(.small) private var captionGap
    private let dotDiameter: CGFloat = 16
    private let dotGap: CGFloat = 8

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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: day))
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
