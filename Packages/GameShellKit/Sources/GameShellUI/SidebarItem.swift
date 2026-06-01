// SidebarItem — a config row in RootShellView's regular-size-class sidebar.
//
// Each game's RootView builds an array of these and hands them to
// `RootShellView`. The shell renders the list; the caller's `onTap`
// closure decides whether the tap pushes a route, runs a side effect
// (e.g. presenting a system modal like the Game Center dashboard), or
// both.

public import SwiftUI

public struct SidebarItem<Route: Hashable>: Identifiable {

    /// Stable identifier for SwiftUI `ForEach` diffing. Callers pick a
    /// route-shaped slug (e.g. "daily", "leaderboard") — kept opaque to
    /// the shell so it can't be coupled to a specific Route enum.
    public let id: String

    /// Localized label rendered with `Label(_:systemImage:)`.
    public let titleKey: LocalizedStringKey

    /// SF Symbol name displayed alongside the label.
    public let systemImage: String

    /// Tap handler. Closure rather than enum so the shell stays unaware of
    /// route-push vs. side-effect distinctions (e.g. GameCenter dashboard
    /// presents a sheet, not a route push).
    public let onTap: @MainActor () -> Void

    public init(
        id: String,
        titleKey: LocalizedStringKey,
        systemImage: String,
        onTap: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.onTap = onTap
    }
}
