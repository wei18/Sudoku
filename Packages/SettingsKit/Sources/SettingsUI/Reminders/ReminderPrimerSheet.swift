// ReminderPrimerSheet — the generic soft pre-ask primer (#287 Phase 2).
//
// Shared chrome (proposal §4.4 Q2 → GameShellUI) so Sudoku + Minesweeper render
// an identical sheet with copy INJECTED. Mirrors the flow-visual S03: a bottom
// sheet with a sage icon tile, title, lede, a 3-bullet "promise" block, a
// prominent accept CTA + a plain repeatable "Not now". This view is presentation
// only — the host owns *when* it shows; the CTAs call back out.
//
// Theme via `@Environment(\.theme)` (the host injects its concrete palette —
// Sudoku's `DefaultTheme`). Touch targets ≥ 44pt; `.contentShape(Rectangle())`
// on the tappable rows (swiftui-interaction-footguns: Spacer/padding don't grow
// the hit region under custom gestures/plain buttons).
//
// Theme machinery (`EnvironmentValues.theme`, `NeutralTheme` default) lives in
// GameShellUI; SettingsUI depends on it for these two themed sheets. The `theme`
// is read only inside the view bodies (not in any public signature), so the
// import is `internal` (impl-notes 2026-06-09 D1).
//
// R6.1–R6.4 fixes (SDD-003 Epic 6):
//   R6.1 — `.contentShape(Rectangle())` removed from inside `acceptButton` label
//           (`.borderedProminent` owns its own hit-test boundary; the inner
//           contentShape was silently widening the button's press region into
//           surrounding non-interactive content). For `declineButton`, `.plain`
//           style collapses hit region to drawn text — moved contentShape to the
//           Button level (after `.buttonStyle`) so only the visible row is
//           interactive and no invisible rectangle bleeds into the sheet body.
//   R6.2 — `declineButton` switches from `.plain` to `DeclineButtonStyle`, a
//           local `ButtonStyle` that animates opacity on press and shows a subtle
//           rounded-rectangle highlight on focus (keyboard / TV-style nav).
//           VoiceOver keeps the button role automatically — SwiftUI propagates
//           it through `ButtonStyle`.
//   R6.3 — Detent restriction lives in the presenter (`ReminderSettingsSection`):
//           `.presentationDetents([.medium])` (single) and
//           `.presentationDragIndicator(.hidden)` prevent drag-up layout breakage.
//   R6.4 — Icon tile uses `@ScaledMetric` so it contracts at AX3+. Title / lede
//           add `.minimumScaleFactor(0.75)` so text never truncates on narrow
//           SE-class widths. All `Text` views already have no fixed heights — the
//           `VStack` allows free vertical growth. `fixedSize` is NOT applied
//           anywhere, letting every element wrap naturally.

public import SwiftUI
internal import GameShellUI

// MARK: - Copy value type (fully injected)

/// All user-facing strings for the primer + denial explainer, injected by the
/// host from its own `Localizable.xcstrings`. The shared view hard-codes none of
/// it (proposal §3.3 / §4.1). `LocalizedStringKey` so each app's catalog
/// localizes the literals passed at the call site.
///
/// Not `Sendable` — `LocalizedStringKey` isn't `Sendable`, and this value is
/// built + consumed entirely on `@MainActor` (the call site + the view body),
/// so it never crosses an actor boundary.
public struct ReminderPrimerCopy: Equatable {
    public var title: LocalizedStringKey
    public var lede: LocalizedStringKey
    public var bullets: [LocalizedStringKey]
    public var acceptCTA: LocalizedStringKey
    public var declineCTA: LocalizedStringKey
    public var fineprint: LocalizedStringKey

    public init(
        title: LocalizedStringKey,
        lede: LocalizedStringKey,
        bullets: [LocalizedStringKey],
        acceptCTA: LocalizedStringKey,
        declineCTA: LocalizedStringKey,
        fineprint: LocalizedStringKey
    ) {
        self.title = title
        self.lede = lede
        self.bullets = bullets
        self.acceptCTA = acceptCTA
        self.declineCTA = declineCTA
        self.fineprint = fineprint
    }
}

// MARK: - Decline button style (R6.2)

/// A `ButtonStyle` for the "Not Now" row that provides pressed-state opacity
/// feedback and a keyboard-focus highlight ring. `.plain` gives no visual
/// feedback at all; `.bordered` is too heavy for a secondary dismiss action.
///
/// Behaviour:
/// - Pressed → opacity 0.5, animated with spring(duration: 0.15)
/// - Focused (hardware keyboard / TV navigation) → rounded-rectangle stroke
/// - Reduced-motion → no animation, just the final opacity value
///
/// `internal` (not `private`) — #762 PR2 extracted `ReminderDeniedExplainer`
/// into its own sibling file (400-line ceiling), and it reuses this style.
struct DeclineButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1.0)
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .padding(-4)
                }
            }
            .animation(reduceMotion ? nil : .spring(duration: 0.15), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.1), value: isFocused)
    }
}

// MARK: - Primer sheet

public struct ReminderPrimerSheet: View {
    private let copy: ReminderPrimerCopy
    private let isRequesting: Bool
    private let onAccept: () -> Void
    private let onDecline: () -> Void

    @Environment(\.theme) private var theme

    // R6.4: icon tile contracts at AX text sizes so the sheet still fits.
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 60

    // Sheet content padding (#762 PR2 two-tier spacing contract) — content
    // tier, wraps the whole icon/title/lede/promise/CTA/fineprint column,
    // scales with Dynamic Type. Independent of `iconSize` above (R6.4) —
    // does not change that mechanism's AX-contraction behavior.
    @ScaledSpacing(.large) private var sheetPadding
    // Content rhythm between the sheet's major sections — content tier.
    @ScaledSpacing(.medium) private var contentGap
    // Content rhythm within a section (e.g. the two CTA buttons, or the
    // promise-block bullets) — content tier.
    @ScaledSpacing(.small) private var rowGap

    /// - Parameters:
    ///   - copy: localized strings (host-provided).
    ///   - isRequesting: drives the accept CTA spinner while the system prompt
    ///     is in flight (bind to `ReminderPermissionModel.isRequesting`).
    ///   - onAccept: user accepted → host calls `requestFromPrimer()`.
    ///   - onDecline: user tapped "Not now" → host dismisses (repeatable, no
    ///     system prompt).
    public init(
        copy: ReminderPrimerCopy,
        isRequesting: Bool = false,
        onAccept: @escaping () -> Void,
        onDecline: @escaping () -> Void
    ) {
        self.copy = copy
        self.isRequesting = isRequesting
        self.onAccept = onAccept
        self.onDecline = onDecline
    }

    public var body: some View {
        // R6.3/R6.4 interplay: the sheet is locked to a single .medium detent, so
        // at AX text sizes the content can exceed the detent height. ScrollView
        // keeps the fineprint and decline button reachable instead of clipped.
        ScrollView {
            VStack(spacing: contentGap) {
                iconTile
                // spacing-exempt: 6pt (title-to-lede gap) predates the
                // 5-tier `SpacingTokens` scale — no matching tier without
                // snapping and changing this sheet's existing
                // layout/snapshot (#762 PR2).
                VStack(spacing: 6) {
                    // R6.4: minimumScaleFactor prevents truncation on SE-class widths
                    // and at AX text sizes; lineLimit(nil) keeps multiline wrapping.
                    Text(copy.title)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.75)
                        .lineLimit(nil)
                        .foregroundStyle(theme.text.primary.resolved)
                    Text(copy.lede)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.75)
                        .lineLimit(nil)
                        .foregroundStyle(theme.text.secondary.resolved)
                }
                promiseBlock
                VStack(spacing: rowGap) {
                    acceptButton
                    declineButton
                }
                Text(copy.fineprint)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.text.tertiary.resolved)
            }
            .padding(sheetPadding)
            .frame(maxWidth: .infinity)
        }
        .background(theme.surface.elevated.resolved)
        // #940 regression anchor: a locale-independent identifier on the
        // sheet's own root, so an E2E test can assert the primer is STILL
        // presented after the async permission-status write that used to
        // race it down (the root cause this issue fixed) without depending
        // on any localized copy.
        .accessibilityIdentifier("reminders.primer.sheet")
    }

    // R6.4: `iconSize` from `@ScaledMetric` shrinks proportionally at AX3+.
    private var iconTile: some View {
        let clampedSize = min(iconSize, 80)
        return Image(systemName: "bell.badge")
            .font(.system(size: clampedSize * 0.47))
            .foregroundStyle(theme.accent.primary.resolved)
            .frame(width: clampedSize, height: clampedSize)
            .background(
                theme.accent.muted.resolved.opacity(0.4),
                in: .rect(cornerRadius: clampedSize * 0.267)
            )
            .accessibilityHidden(true)
    }

    private var promiseBlock: some View {
        VStack(alignment: .leading, spacing: rowGap) {
            ForEach(Array(copy.bullets.enumerated()), id: \.offset) { _, bullet in
                // spacing-exempt: 9pt (checkmark-to-text gap) predates the
                // 5-tier `SpacingTokens` scale — no matching tier without
                // snapping and changing this block's existing
                // layout/snapshot (#762 PR2).
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(theme.accent.primary.resolved)
                        .accessibilityHidden(true)
                    Text(bullet)
                        .font(.footnote)
                        .foregroundStyle(theme.text.primary.resolved)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        // spacing-exempt: 14pt (block padding) predates the 5-tier
        // `SpacingTokens` scale — no matching tier to route through
        // without snapping to a neighbor and changing this block's
        // existing layout/snapshot. Tracked as a follow-up once the
        // token-scale gap gets an owner decision (#762 PR2).
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(theme.accent.muted.resolved.opacity(0.25), in: .rect(cornerRadius: 12))
    }

    // R6.1: Removed the `.contentShape(Rectangle())` from inside the label.
    // `.borderedProminent` manages its own visual + hit region. The inner
    // contentShape was silently expanding the tappable zone into adjacent content.
    private var acceptButton: some View {
        Button(action: onAccept) {
            // #797 (CR round 2): `.borderedProminent`'s system-default white
            // label (and the spinner's old `.tint(.white)`) hard-fail AA
            // against the dark-mode accent.primary on both apps' ramps
            // (Sudoku sage 0x9BB87E = 2.20:1; MS blue 0x7FAFCF = 2.35:1).
            // Same #786/#797 pattern as the shared overlay CTAs:
            // `surface.primary` ink (white light / dark surface dark) clears
            // 4.5:1 on both ramps (Sudoku 4.83/7.42, MS 5.70/6.96 —
            // light/dark). MUST sit on the label content, not chained after
            // `.buttonStyle` — the prominent style ignores an ambient
            // `.foregroundStyle` set on the Button itself. Light mode renders
            // byte-identically (surface.primary light is white).
            Group {
                if isRequesting {
                    ProgressView()
                        .tint(theme.surface.primary.resolved)
                } else {
                    Text(copy.acceptCTA)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(theme.surface.primary.resolved)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            // spacing-exempt: 11pt predates the 5-tier `SpacingTokens`
            // scale — no matching tier without snapping and changing this
            // button's existing layout/snapshot (#762 PR2).
            .padding(.vertical, 11)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(theme.accent.primary.resolved)
        .disabled(isRequesting)
    }

    // R6.1: `.contentShape(Rectangle())` is now on the Button exterior (after
    // `.buttonStyle`) so the hit region matches the visual label row without
    // bleeding into surrounding non-interactive content.
    // R6.2: `DeclineButtonStyle` provides pressed-opacity + focus-ring feedback.
    private var declineButton: some View {
        Button(action: onDecline) {
            Text(copy.declineCTA)
                .font(.body.weight(.medium))
                .foregroundStyle(theme.text.secondary.resolved)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(DeclineButtonStyle())
        .contentShape(Rectangle())
        .disabled(isRequesting)
    }
}
