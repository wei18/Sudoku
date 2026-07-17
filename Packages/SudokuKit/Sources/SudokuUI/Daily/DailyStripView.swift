// DailyStripView — the rolling 7-day completion strip + streak caption.
//
// #774. Injected into `DailyHubShellView`'s generic `header` slot (#840) by
// `DailyHubView` — GameShellKit's shell stays untouched (it only knows
// `Header: View`), keeping the "no shared streak-widget abstraction" scope
// note (proposal §7) literal: this whole file is per-app, copy-paste-adapted
// into `MinesweeperUI.MinesweeperDailyStripView`. The shell renders `header`
// in every load state and, for `.loaded`, inside the same `ScrollView` as
// the card grid — so the strip scrolls WITH the trio instead of staying
// pinned above it (#840 — owner-reported regression from #774's original
// "fixed sibling above the shell" placement).
//
// Interaction scope (#826, owner adjudication 2026-07-16): a COMPLETED PAST
// day's dot is a button — tap opens that day's Completion review (exactly one
// completed difficulty → direct open; more than one → a confirmationDialog
// picker, hosted by `DailyHubView`). Today's dot and any missed/empty day
// stay inert, matching the original v1 scope note this comment used to carry.
// 44pt tap target via `.contentShape` inset, dot stays 16pt visually —
// `isTappable(_:)` below is the single source of truth both the dot's Button
// wrapping and its a11y traits read from.
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
    /// #826: fired only for a tappable dot (`isTappable(_:)` == true) — the
    /// host (`DailyHubView`) forwards this straight to
    /// `DailyHubViewModel.dayTapped`. Defaulted so existing call sites
    /// (previews, any snapshot fixture) keep compiling untouched.
    var onDayTap: (DailyStripDay) -> Void = { _ in }
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
    // #826: 44pt is the standard iOS minimum tap target; applied via a
    // `.contentShape` inset (below) so it never changes the dot's own
    // layout footprint in the HStack — the row's width/gaps stay pixel
    // identical to the pre-#826 baseline.
    private let tapTargetDiameter: CGFloat = 44

    /// #826: a dot becomes a button iff it is a REVIEWABLE, PAST day —
    /// today's dot and any missed/empty day stay inert (owner adjudication
    /// 2026-07-16). `isReviewable` (not raw `isCompleted`) is the gate: a
    /// completed day whose ids are ALL malformed can't open anything, so it
    /// must not grow a button/trait/hint either (CR round 2) —
    /// `DailyStripDay.isReviewable` derives from the same
    /// `DailyStripLogic.reviewChoices` parse `dayTapped` uses. Single source
    /// of truth for both the Button wrapping in `dotView(for:)` and its a11y
    /// traits — tested directly (`@testable`) without standing up a
    /// rendering harness, mirroring `BoardCellView.isInteractive`.
    func isTappable(_ day: DailyStripDay) -> Bool {
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
        if isTappable(day) {
            Button {
                onDayTap(day)
            } label: {
                dotShape(for: day)
            }
            .buttonStyle(.plain)
            // Enlarges the hit-test area to the 44pt minimum without
            // affecting this view's own reported size in the parent HStack
            // (`.contentShape` never changes layout, only what responds to
            // gestures) — the dot row's width/gaps stay byte-identical to
            // the inert baseline.
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
    private func dotShape(for day: DailyStripDay) -> some View {
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

    /// #826: VoiceOver hint appended only to tappable (past + completed)
    /// dots — the label itself (`accessibilityLabel(for:)`) is unchanged for
    /// every dot, tappable or not.
    private var reviewHint: String {
        String(localized: "View this day's result", bundle: .main)
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
