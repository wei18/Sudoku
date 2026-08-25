// AppTab — the three top-level tab identities every game's root shell shows
// (#1020, design.md §2.1 / §2.2).
//
// v3.0 replaces the single-path `home → daily/practice/settings/stats` route
// table with a `sidebarAdaptable` `TabView`. `daily` / `practice` / `stats`
// stop being routes and become tab IDENTITIES; `home` is deleted outright.
// One artifact serves the iPhone tab bar and the iPad/macOS sidebar (HIG
// *Sidebars*), so this enum is the single source of truth for both surfaces —
// there is no hand-authored sidebar list any more.
//
// `Codable` so a host can persist / restore the selected tab without the shell
// owning a storage seam; `Sendable` because it crosses into `GameAppKit`'s
// `@MainActor @Observable` root VM and its tests.
//
// Titles are `LocalizedStringKey` rendered with `Text(_:)` / `Tab(_:…)`, which
// resolve against `Bundle.main` — each APP's `Localizable.xcstrings` supplies
// the translation, exactly like the retired `HomeMode.titleKey` did.
// GameShellUI ships no string catalog of its own.

public import SwiftUI

public enum AppTab: String, Hashable, CaseIterable, Sendable, Codable {
    /// Daily puzzles + the resume pill + the banner slot (the ATT anchor, C-33).
    case today
    /// Free-play / difficulty selection.
    case practice
    /// Statistics + the Game Center `Achievements` entry point (C-36).
    case progress

    /// Canonical localized tab title.
    public var titleKey: LocalizedStringKey {
        switch self {
        case .today: "Today"
        case .practice: "Practice"
        case .progress: "Progress"
        }
    }

    /// Canonical SF Symbol. Carried over from the surfaces these tabs replace so
    /// the glyph a player learned does not move: `calendar` was `HomeMode.daily`,
    /// `dice` was `HomeMode.practice`, `chart.bar` was the #773/#844 Statistics
    /// entry.
    public var systemImage: String {
        switch self {
        case .today: "calendar"
        case .practice: "dice"
        case .progress: "chart.bar"
        }
    }
}
