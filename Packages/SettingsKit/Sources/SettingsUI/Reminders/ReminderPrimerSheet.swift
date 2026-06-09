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

// MARK: - Primer sheet

public struct ReminderPrimerSheet: View {
    private let copy: ReminderPrimerCopy
    private let isRequesting: Bool
    private let onAccept: () -> Void
    private let onDecline: () -> Void

    @Environment(\.theme) private var theme

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
        VStack(spacing: 16) {
            iconTile
            VStack(spacing: 6) {
                Text(copy.title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.text.primary.resolved)
                Text(copy.lede)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.text.secondary.resolved)
            }
            promiseBlock
            VStack(spacing: 8) {
                acceptButton
                declineButton
            }
            Text(copy.fineprint)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.text.tertiary.resolved)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(theme.surface.elevated.resolved)
    }

    private var iconTile: some View {
        Image(systemName: "bell.badge")
            .font(.system(size: 28))
            .foregroundStyle(theme.accent.primary.resolved)
            .frame(width: 60, height: 60)
            .background(theme.accent.muted.resolved.opacity(0.4), in: .rect(cornerRadius: 16))
            .accessibilityHidden(true)
    }

    private var promiseBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(copy.bullets.enumerated()), id: \.offset) { _, bullet in
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
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(theme.accent.muted.resolved.opacity(0.25), in: .rect(cornerRadius: 12))
    }

    private var acceptButton: some View {
        Button(action: onAccept) {
            Group {
                if isRequesting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(copy.acceptCTA)
                        .font(.body.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(theme.accent.primary.resolved)
        .disabled(isRequesting)
    }

    private var declineButton: some View {
        Button(action: onDecline) {
            Text(copy.declineCTA)
                .font(.body.weight(.medium))
                .foregroundStyle(theme.text.secondary.resolved)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRequesting)
    }
}

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
        VStack(spacing: 16) {
            Image(systemName: "bell.slash")
                .font(.system(size: 30))
                .foregroundStyle(theme.status.error.resolved)
                .frame(width: 76, height: 76)
                .background(theme.status.error.resolved.opacity(0.12), in: .circle)
                .accessibilityHidden(true)
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
                Label(copy.openSettingsCTA, systemImage: "gearshape")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
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
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(theme.status.warning.resolved.opacity(0.10), in: .rect(cornerRadius: 10))
            #endif

            Button(action: onDismiss) {
                Text(copy.dismissCTA)
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.text.secondary.resolved)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(theme.surface.elevated.resolved)
    }
}
