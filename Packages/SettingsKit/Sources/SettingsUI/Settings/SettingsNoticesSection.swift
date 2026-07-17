// SettingsNoticesSection — app-agnostic Notices / 宣告 section (issue #331).
//
// The one named #331 piece with NO in-app surface before this change.
// Acknowledgements today land in an iOS `Settings.bundle` (system Settings.app
// → <App> → Acknowledgements, via LicensePlist); privacy-policy / support URLs
// live only in ASC metadata. This Section surfaces them inside the app, the
// last shared-Settings building block that both games were still missing.
//
// Shape mirrors the sibling `SettingsAboutStorage.swift` decisions:
//   - the section ships whole (no per-game additions today, unlike About which
//     hosts Sudoku's Generator row);
//   - it carries NO theme dependency — the host passes `tintColor: Color` for
//     the leading SF Symbols (both Sudoku and Minesweeper resolve
//     `theme.accent.primary.resolved` as of #688 item 5a), matching
//     `SettingsAboutVersionRow`;
//   - rows use the HStack + Spacer primitive so `.formStyle(.grouped)` renders
//     full-width pills on macOS (issue #197).
//
// App-injected, not hardcoded: the privacy-policy + support URLs and the
// copyright line are supplied per app (they differ across Sudoku / Minesweeper
// and live in each app's ASC metadata). The acknowledgements destination is a
// host closure (`onAcknowledgements`) so the shared target takes no opinion on
// whether the host pushes a `LicensePlist` view, opens the Settings.bundle, or
// navigates elsewhere — no monetization / no UserNotifications / no LicensePlist
// import leaks into GameShellUI.

public import SwiftUI

/// App-injected inputs for `SettingsNoticesSection`. A plain value the host
/// (RouteFactory / LiveRouteFactory) constructs once and passes through its
/// game's `SettingsView`, so the per-app URLs + copyright + acknowledgements
/// deep-link live at the composition root, not hardcoded in the shared target.
/// All fields optional — an app supplies only the notices it has.
public struct SettingsNoticesConfig: Sendable {
    public let onAcknowledgements: (@MainActor () -> Void)?
    public let privacyPolicyURL: URL?
    public let supportURL: URL?
    public let copyright: String?

    public init(
        onAcknowledgements: (@MainActor () -> Void)? = nil,
        privacyPolicyURL: URL? = nil,
        supportURL: URL? = nil,
        copyright: String? = nil
    ) {
        self.onAcknowledgements = onAcknowledgements
        self.privacyPolicyURL = privacyPolicyURL
        self.supportURL = supportURL
        self.copyright = copyright
    }
}

/// `Section("Notices")` hosting legal/about entries: Acknowledgements (host
/// action), Privacy Policy + Support (external `Link`s), and a copyright line.
/// Each row is optional — pass `nil` to omit it — so an app that has, say, no
/// public support page renders a smaller section without a placeholder row.
public struct SettingsNoticesSection: View {
    private let tintColor: Color
    private let onAcknowledgements: (@MainActor () -> Void)?
    private let privacyPolicyURL: URL?
    private let supportURL: URL?
    private let copyright: String?

    public init(
        tintColor: Color,
        onAcknowledgements: (@MainActor () -> Void)? = nil,
        privacyPolicyURL: URL? = nil,
        supportURL: URL? = nil,
        copyright: String? = nil
    ) {
        self.tintColor = tintColor
        self.onAcknowledgements = onAcknowledgements
        self.privacyPolicyURL = privacyPolicyURL
        self.supportURL = supportURL
        self.copyright = copyright
    }

    /// Convenience init from the host-supplied `SettingsNoticesConfig`.
    public init(tintColor: Color, config: SettingsNoticesConfig) {
        self.init(
            tintColor: tintColor,
            onAcknowledgements: config.onAcknowledgements,
            privacyPolicyURL: config.privacyPolicyURL,
            supportURL: config.supportURL,
            copyright: config.copyright
        )
    }

    public var body: some View {
        Section("Notices") {
            if let onAcknowledgements {
                Button(action: onAcknowledgements) {
                    NoticeRowLabel(
                        systemImage: "doc.text",
                        title: "Acknowledgements",
                        tintColor: tintColor,
                        showsDisclosure: true
                    )
                }
                .buttonStyle(.plain)
            }

            if let privacyPolicyURL {
                Link(destination: privacyPolicyURL) {
                    NoticeRowLabel(
                        systemImage: "hand.raised",
                        title: "Privacy Policy",
                        tintColor: tintColor,
                        showsDisclosure: true
                    )
                }
            }

            if let supportURL {
                Link(destination: supportURL) {
                    NoticeRowLabel(
                        systemImage: "questionmark.circle",
                        title: "Support",
                        tintColor: tintColor,
                        showsDisclosure: true
                    )
                }
            }

            if let copyright {
                HStack {
                    // #845: `Label` icon column (was a raw `Image + Text`
                    // HStack) — matches the standard row shape below.
                    Label {
                        Text(verbatim: copyright)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "c.circle")
                            .foregroundStyle(tintColor)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Shared row label for the Notices section: icon-left / title / spacer /
/// optional trailing chevron, stretched full-width for the grouped-Form pill
/// treatment on macOS (issue #197). `tintColor` colors the leading symbol so
/// the row carries no theme dependency.
private struct NoticeRowLabel: View {
    let systemImage: String
    let title: LocalizedStringKey
    let tintColor: Color
    let showsDisclosure: Bool

    var body: some View {
        HStack {
            // #845: `Label` icon column (was a raw `Image + Text` HStack) —
            // Acknowledgements / Privacy Policy / Support shared the same
            // tighter gap as the About rows; converge to the standard shape.
            Label {
                Text(title)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(tintColor)
            }
            Spacer()
            if showsDisclosure {
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
