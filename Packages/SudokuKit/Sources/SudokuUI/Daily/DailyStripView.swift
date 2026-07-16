// DailyStripView — the rolling 7-day completion strip + streak caption.
//
// #774. Renders above `DailyHubShellView` inside `DailyHubView` (own file,
// own VStack — GameShellKit's `DailyHubShellView` is untouched, keeping the
// "no shared streak-widget abstraction" scope note (proposal §7) literal:
// this whole file is per-app, copy-paste-adapted into
// `MinesweeperUI.MinesweeperDailyStripView`).
//
// Interaction scope: this is a VIEW-ONLY strip in v1 — no dot is tappable.
// The proposal's "tap a past completed day → that day's completion review"
// interaction is NOT implemented here: Sudoku's `.completion` route already
// carries a `puzzleId` so it could resolve, but Minesweeper's `.completion`
// route (`AppRoute.completion(difficulty:mode:)`) carries no date/seed at
// all — it always resolves to *today's* board for that difficulty. Wiring
// past-day review navigation would mean widening that route's signature (a
// real behavior change to shared navigation, not a data/presentation change),
// which is out of scope for this dispatch. "Tap a future day is a no-op" and
// "tap a past incomplete day is a no-op" both hold trivially as a result.
// See the dispatch report for the explicit flag to the owner/Leader.
//
// Dot states (proposal §3.1 / §3.5, owner adjudication 2026-07-15):
//   - completed (today or past): filled `accent.primary`.
//   - today, not completed: `accent.primary` stroke only, no fill.
//   - past, not completed: `text.tertiary`-toned, low emphasis.
// "Future day" never occurs — the strip is a ROLLING 7-day window ending at
// today (owner adjudication item 3), not a calendar week, so there is no
// future slot to render in the first place.

import SwiftUI
internal import GameShellUI

struct DailyStripView: View {
    let snapshot: DailyStripSnapshot
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Content tier (#762 two-tier contract): the gap between the dot row and
    // the streak caption sits directly under a text row, scales with
    // Dynamic Type.
    @ScaledSpacing(.small) private var captionGap
    // Structural tier: dot geometry + inter-dot gap are fixed — 7 dots must
    // never wrap or reflow at any Dynamic Type size (proposal §3.4 / issue
    // #774 acceptance checklist). 16pt matches the existing 4pt spacing
    // ladder (4 × 4); 8pt gap matches `SpacingTokens.small`.
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
                // Two keys instead of one interpolated "%@ day streak": the
                // capped display ("7+") is a string, which would make the
                // exact-count case un-pluralizable (es needs día/días
                // agreement, which only a %lld plural-variation key gives).
                // 7 == the fetch window size — the streak saturates there
                // (see `DailyStripLogic.computeStreak`), so ≥7 means "at
                // least 7, window can't prove more".
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
        // Without this the VStack shrinks to its content and the parent
        // centers it, leaving the strip floating mid-screen while the trio
        // cards below sit at the leading screen-edge inset (caught by
        // eyeballing the first recorded baseline — the layout gate can't
        // see misalignment).
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: snapshot)
    }

    private var placeholderDot: some View {
        Circle()
            .strokeBorder(theme.text.tertiary.resolved.opacity(0.3), lineWidth: 1)
            .frame(width: dotDiameter, height: dotDiameter)
    }

    @ViewBuilder
    private func dotView(for day: DailyStripDay) -> some View {
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

    /// "Monday, completed" / "Wednesday, today, not yet completed" /
    /// "Friday, missed" — one combined VoiceOver element per dot (proposal
    /// §3.4 / issue #774 acceptance checklist), never seven unlabeled shapes.
    private func accessibilityLabel(for day: DailyStripDay) -> String {
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
