// DailyStripView — the rolling 7-day completion strip + streak caption,
// rendered as a card-contained calendar strip (#843 redesign, Option A —
// owner adjudication 2026-07-17: the pre-#843 bare-dot-row read as
// "decorative dots, not a calendar", `docs/.../design-843/issue-843-daily-
// streak.md`).
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
// stay inert. 44pt tap target via `.contentShape` inset, dot stays a fixed
// visual diameter — `isTappable(_:)` below is the single source of truth
// both the dot's Button wrapping and its a11y traits read from. Untouched by
// #843 (visual-only redesign).
//
// Card anatomy (#843 Option A):
//   - Container: rounded card, `surface.elevated` fill + hairline
//     `text.tertiary` stroke — the same "how we do elevated surfaces"
//     language proposed for #846's completion card, not a one-off.
//   - Header row (flame icon + streak caption): renders only when
//     `snapshot.streak != nil` — hidden entirely at streak 0, exactly as
//     before #843 (`DailyHubViewModel` already nils the streak at 0).
//   - Dot row: 7 columns, each a dot + `Calendar.veryShortWeekdaySymbols`
//     weekday initial — locale-correct automatically, NOT a new
//     translatable string.
//   - Degrade (#843, supersedes the pre-#843 subdued-skeleton-dots
//     treatment): `snapshot.days.isEmpty` (unknown / CK-fetch failure) omits
//     the WHOLE card from layout — no partial/skeleton render (design-db
//     `states.md`: skeleton states are low-confidence, don't fake them).
//
// Dot states (#843 spec §Option A — the "unknown-degraded" 4th state from
// the spec's own dot-state list is dropped: the all-or-nothing degrade gate
// above means an individual day can never independently be in an unknown
// state, so a per-dot degraded case would be unreachable dead code, exactly
// as the spec's own "flag to implementer" callout anticipated):
//   - completed: filled `accent.primary`, checkmark inked via
//     `surface.onTintInk(for: accent.primary)` (#786/#797 on-accent-ink
//     contract).
//   - today, not completed: dashed `accent.primary` stroke, no fill —
//     visually distinct from both completed (filled) and missed (thin solid
//     outline).
//   - past, not completed (missed): `text.tertiary`-toned solid outline, no
//     fill.
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

    // Content tier (#762 two-tier contract): gaps/padding adjacent to text
    // or icons scale with Dynamic Type.
    @ScaledSpacing(.small) private var headerToDotGap
    @ScaledSpacing(.medium) private var cardPadding
    @ScaledSpacing(.extraSmall) private var headerIconGap

    // Structural tier: dot geometry, inter-dot gap, and the dot→weekday-
    // initial gap are fixed — 7 dots must never wrap or reflow at any
    // Dynamic Type size (#843 spec §Dynamic Type / AX3; issue #774
    // acceptance checklist). 28pt is the #843-specified visual dot diameter
    // (was 16pt pre-redesign); 8pt gap matches `SpacingTokens.small`.
    private let dotDiameter: CGFloat = 28
    private let dotGap: CGFloat = 8
    private let dotLabelGap: CGFloat = 4
    private let cardCornerRadius: CGFloat = 16
    // #826: 44pt is the standard iOS minimum tap target; applied via a
    // `.contentShape` inset (below) so it never changes the dot's own
    // layout footprint in the HStack.
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
        if snapshot.days.isEmpty {
            // #843: all-or-nothing degrade — the whole card is omitted from
            // layout rather than showing a subdued skeleton (see the file
            // header comment's "Degrade" note).
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
        // cap — the dot row below stays structural-tier regardless.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .combine)
    }

    /// Two keys instead of one interpolated "%@ day streak": the capped
    /// display ("7+") is a string, which would make the exact-count case
    /// un-pluralizable (es needs día/días agreement, which only a %lld
    /// plural-variation key gives). 7 == the fetch window size — the streak
    /// saturates there (see `DailyStripLogic.computeStreak`), so ≥7 means
    /// "at least 7, window can't prove more". Reuses the existing keys
    /// verbatim (no new L10n) — kept as ONE `Text`, not a bold-numeral +
    /// plain-suffix split, because several locales (es/ja/ko/th/zh) place
    /// the numeral mid-sentence rather than at a fixed prefix, so the
    /// spec's two-style header typography isn't representable without
    /// re-translating the existing key (#843 spec deviation — see the
    /// dispatch report).
    private func streakCaption(streak: Int) -> Text {
        streak >= 7 ? Text("7+ day streak") : Text("\(streak) day streak")
    }

    private var dotRow: some View {
        HStack(spacing: dotGap) {
            ForEach(snapshot.days) { day in dayColumn(for: day) }
        }
        .accessibilityElement(children: .contain)
    }

    /// One column = a dot + its weekday initial underneath (#843 spec
    /// `VStack(spacing: 4) { dot, weekday-initial }`). The label is
    /// decorative — `accessibilityLabel(for:)` on the dot itself already
    /// speaks the full weekday name + state, so the initial is hidden from
    /// VoiceOver to avoid a double announcement.
    private func dayColumn(for day: DailyStripDay) -> some View {
        VStack(spacing: dotLabelGap) {
            dotView(for: day)
            Text(weekdayInitial(for: day.date))
                .font(.caption2)
                .foregroundStyle(theme.text.tertiary.resolved)
                .accessibilityHidden(true)
        }
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
            // gestures).
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
                Circle()
                    .strokeBorder(theme.text.tertiary.resolved.opacity(0.4), lineWidth: 1)
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

    /// Locale-correct weekday initial ("S", "M", "T", … in en) sourced from
    /// `Calendar.current.veryShortWeekdaySymbols` — NOT a new translatable
    /// string (#843 spec). The symbols array is indexed by the Gregorian
    /// `.weekday` component (1=Sunday…7=Saturday), independent of the
    /// calendar's `firstWeekday`.
    private func weekdayInitial(for date: Date) -> String {
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols
        let index = calendar.component(.weekday, from: date) - 1
        guard symbols.indices.contains(index) else { return "" }
        return symbols[index]
    }
}
