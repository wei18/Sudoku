// ReminderDeniedExplainer — the `.denied` recovery explainer (flow S06).
//
// Extracted from ReminderPrimerSheet.swift (#762 PR2) to keep that file under
// SwiftLint's 400-line ceiling — mirrors the repo convention of splitting a
// sibling file rather than disabling the rule (e.g. GameShellUI's
// BoardView+AccessibilityHeader.swift, MinesweeperKit's SnapshotConfig.swift).
// Shares `DeclineButtonStyle` and the theme/spacing conventions declared in
// ReminderPrimerSheet.swift (same module, same target).

public import SwiftUI
internal import GameShellUI

// MARK: - Denial explainer (S06)

/// Copy for the denial-recovery explainer (flow S06). Separate from the primer
/// copy because it's a distinct surface with its own CTA. Not `Sendable` for the
/// same reason as `ReminderPrimerCopy` (MainActor-only `LocalizedStringKey`).
public struct ReminderDeniedCopy: Equatable {
    public var title: LocalizedStringKey
    public var message: LocalizedStringKey
    public var openSettingsCTA: LocalizedStringKey
    public var dismissCTA: LocalizedStringKey
    /// macOS-only textual guidance shown in place of the deep-link button
    /// (proposal P12 — no AppKit `openNotificationSettingsURLString`).
    public var macOSGuidance: LocalizedStringKey

    public init(
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        openSettingsCTA: LocalizedStringKey,
        dismissCTA: LocalizedStringKey,
        macOSGuidance: LocalizedStringKey
    ) {
        self.title = title
        self.message = message
        self.openSettingsCTA = openSettingsCTA
        self.dismissCTA = dismissCTA
        self.macOSGuidance = macOSGuidance
    }
}

/// The `.denied` explainer (S06): icon + title + message, then on iOS an
/// "Open Settings" deep-link button; on macOS, textual guidance (P12 gap).
public struct ReminderDeniedExplainer: View {
    private let copy: ReminderDeniedCopy
    private let onOpenSettings: () -> Void
    private let onDismiss: () -> Void

    @Environment(\.theme) private var theme

    // Sheet content padding + section rhythm (#762 PR2 two-tier spacing
    // contract) — content tier, scales with Dynamic Type. Same rationale
    // as `ReminderPrimerSheet`'s equivalents.
    @ScaledSpacing(.large) private var sheetPadding
    @ScaledSpacing(.medium) private var contentGap

    public init(
        copy: ReminderDeniedCopy,
        onOpenSettings: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.copy = copy
        self.onOpenSettings = onOpenSettings
        self.onDismiss = onDismiss
    }

    public var body: some View {
        // #673: background moved from the VStack onto the ScrollView (mirrors
        // ReminderPrimerSheet's R6.3/R6.4 structure). The intrinsically
        // sized VStack was shorter than the .medium detent, so its background
        // stopped short and the system sheet material showed as a darker band
        // above the content; the ScrollView fills the full detent instead.
        ScrollView {
            VStack(spacing: contentGap) {
                Image(systemName: "bell.slash")
                    .font(.system(size: 30))
                    .foregroundStyle(theme.status.error.resolved)
                    .frame(width: 76, height: 76)
                    .background(theme.status.error.resolved.opacity(0.12), in: .circle)
                    .accessibilityHidden(true)
                // spacing-exempt: 6pt (title-to-message gap) predates the
                // 5-tier `SpacingTokens` scale — same rationale as
                // `ReminderPrimerSheet`'s equivalent (#762 PR2).
                VStack(spacing: 6) {
                    Text(copy.title)
                        .font(.title3.weight(.bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(theme.text.primary.resolved)
                    Text(copy.message)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(theme.text.secondary.resolved)
                }

                #if canImport(UIKit)
                Button(action: onOpenSettings) {
                    // #797 (CR round 2): same on-accent-ink fix + label-content
                    // placement as `acceptButton` above.
                    Label(copy.openSettingsCTA, systemImage: "gearshape")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 28)
                        // spacing-exempt: 11pt predates the 5-tier
                        // `SpacingTokens` scale — same rationale as
                        // `acceptButton`'s equivalent (#762 PR2).
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                        .foregroundStyle(theme.surface.primary.resolved)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(theme.accent.primary.resolved)
                #else
                // macOS (P12): no deep-link. Show textual guidance instead.
                Text(copy.macOSGuidance)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.text.secondary.resolved)
                    // spacing-exempt: 12pt predates the 5-tier
                    // `SpacingTokens` scale — no matching tier without
                    // snapping and changing this card's existing
                    // layout/snapshot (#762 PR2).
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(theme.status.warning.resolved.opacity(0.10), in: .rect(cornerRadius: 10))
                #endif

                // R6.1/R6.2 (same pattern as declineButton): hit region scoped to the
                // button frame, pressed/focus feedback via DeclineButtonStyle.
                Button(action: onDismiss) {
                    Text(copy.dismissCTA)
                        .font(.body.weight(.medium))
                        .foregroundStyle(theme.text.secondary.resolved)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(DeclineButtonStyle())
                .contentShape(Rectangle())
            }
            .padding(sheetPadding)
            .frame(maxWidth: .infinity)
        }
        .background(theme.surface.elevated.resolved)
    }
}
