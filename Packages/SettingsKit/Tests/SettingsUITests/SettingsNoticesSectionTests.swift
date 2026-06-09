import SwiftUI
import Testing
@testable import SettingsUI

// MARK: - SettingsNoticesSection (issue #331)
//
// The shared Notices / 宣告 section — the one #331-named Settings piece that
// had no in-app surface before. These tests pin two contracts:
//   1. genericity / theme-decoupling — it instantiates with a bare `Color`
//      tint and no SudokuUI / monetization / LicensePlist types, so it can be
//      mounted by either game (compile-only sentinel, mirrors the sibling
//      SettingsShellView / SettingsAboutStorage sentinels);
//   2. each row is independently optional — a host can omit any of
//      acknowledgements / privacy / support / copyright and still build.

@Suite("GameShellUI — SettingsNoticesSection")
struct SettingsNoticesSectionTests {

    @Test @MainActor func instantiatesFullyPopulated() {
        let section = SettingsNoticesSection(
            tintColor: .accentColor,
            onAcknowledgements: {},
            privacyPolicyURL: URL(string: "https://example.com/privacy"),
            supportURL: URL(string: "https://example.com/support"),
            copyright: "© 2026 Sentinel"
        )
        _ = section
    }

    @Test @MainActor func instantiatesWithOnlyTint() {
        // All optional rows omitted — the section still builds (renders an
        // empty Section, which a host without any notices yet can mount).
        let section = SettingsNoticesSection(tintColor: .accentColor)
        _ = section
    }

    @Test @MainActor func instantiatesInsideSharedShell() {
        // Mounts the section through the generic SettingsShellView — the exact
        // composition both apps use — proving the two shared pieces compose
        // without any app-specific type.
        let shell = SettingsShellView(title: "Sentinel") {
            SettingsNoticesSection(
                tintColor: .accentColor,
                privacyPolicyURL: URL(string: "https://example.com")
            )
        }
        _ = shell
    }
}
