// TodayLoadFailureCaption — TODAY's `degraded(reason: .loadFailed)` state
// (#1021 CR3, design.md §3.1's `degraded` row). Reverses the CR2 regression
// that made a phase-1 daily-load failure render three inert "Not started"
// skeleton cards with NO error signal at all — #768 deliberately replaced a
// system `.alert` with a *visible, recoverable inline failure*, and CR2's
// card-only render silently dropped that signal again. This is the whole
// fix: one content-layer caption row, no rebuilt failure block, no alert.
//
// `completionStatusUnknown` (phase-2 completion-overlay failure) stays
// SILENT exactly as before — thumbnails are seed-derived and real, only the
// checkmark is unknown, which design.md §3.1 accepts as a quiet degrade.
// `loadFailed` (phase-1 — no puzzle data fetched at all) is the one that
// needs an honest caption; see `TodayPresentation.DegradedReason`.
//
// Caller-supplied, ALREADY-localized `text` — mirrors `TodayAllDoneBlock`'s
// shape so this view stays L10n-key-free; each app words (and translates)
// its own message.
//
// Status message, not a control: no retry affordance here. `.isStaticText`
// (not `.isButton`) + an explicit, non-swallowable `.accessibilityLabel` —
// mirrors `StreakHeaderView`'s `.accessibilityElement(children:) +
// .accessibilityLabel(Self.accessibilityLabel(...))` convention so this row
// is never absorbed into a sibling's combined element.

public import SwiftUI

public struct TodayLoadFailureCaption: View {
    @Environment(\.theme) private var theme
    @ScaledSpacing(.extraSmall) private var iconTextGap

    private let text: String
    private let accessibilityIdentifier: String?

    public init(text: String, accessibilityIdentifier: String? = nil) {
        self.text = text
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    public var body: some View {
        if let accessibilityIdentifier {
            row.accessibilityIdentifier(accessibilityIdentifier)
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: iconTextGap) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.status.warning.resolved)
                // Decorative — `text` alone carries the message; the
                // combined element's label below is the text verbatim.
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(theme.text.primary.resolved)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(text: text))
        .accessibilityAddTraits(.isStaticText)
    }

    public static func accessibilityLabel(text: String) -> String {
        text
    }
}
