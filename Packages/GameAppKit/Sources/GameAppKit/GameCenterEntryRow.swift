// GameCenterEntryRow — PROGRESS's two Game Center entry points, `Achievements`
// and `Leaderboards` (#1021 Phase D; generalizes #1020's `AchievementsRow`,
// C-36).
//
// design.md §3.3 pairs the two rows: both open the NATIVE Game Center
// dashboard — **no in-app achievement gallery**. Apple's HIG-mandated
// terminology bans other, more colloquial synonyms for either row's own
// name (see design.md §3.3 for the exact banned list); both rows are in
// GameAppKit (rather than either app's Kit) because both games present an
// identical row (mirror principle).
//
// Both route through `GameRootViewModel.presentGameCenterOrAlert`, the single
// auth gate #685 established — a signed-out tap raises the shared alert
// instead of silently no-op'ing.

public import SwiftUI
// Called only from method bodies (never named in a public signature) — plain
// `import`, not `public import`.
import GameCenterClient
internal import GameShellUI

@MainActor
public struct GameCenterEntryRow<Route: Hashable & Sendable>: View {
    private let title: String
    private let systemImage: String
    private let accessibilityIdentifier: String
    private let rootViewModel: GameRootViewModel<Route>

    /// The presentation side effect, injected so a test can observe it
    /// without standing up GameKit.
    private let present: @MainActor () -> Void

    @Environment(\.theme) private var theme

    public init(
        title: String,
        systemImage: String,
        accessibilityIdentifier: String,
        rootViewModel: GameRootViewModel<Route>,
        present: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accessibilityIdentifier = accessibilityIdentifier
        self.rootViewModel = rootViewModel
        self.present = present
    }

    public var body: some View {
        Button(action: activate) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(theme.accent.primary.resolved)
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.text.primary.resolved)
                Spacer()
                // Outward-jump glyph, not a chevron: this presents Apple's
                // system dashboard as a side effect rather than pushing an
                // in-app destination.
                Image(systemName: "arrow.up.forward")
                    .foregroundStyle(theme.text.tertiary.resolved)
            }
            .padding(12)
            .background(theme.surface.primary.resolved, in: .rect(cornerRadius: 14))
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    /// The row's tap behavior, factored out of the `Button` so the C-36
    /// contract (authenticated → present; signed out → alert, no present) is
    /// unit-testable without rendering.
    func activate() {
        rootViewModel.presentGameCenterOrAlert(present: present)
    }
}

// MARK: - PROGRESS's two rows

extension GameCenterEntryRow {
    /// `Achievements` — a11y id `game.progress.achievements` (kept from
    /// #1020's `AchievementsRow`).
    public static func achievements(rootViewModel: GameRootViewModel<Route>) -> GameCenterEntryRow<Route> {
        GameCenterEntryRow(
            title: String(localized: "Achievements", bundle: .main),
            systemImage: "trophy",
            accessibilityIdentifier: "game.progress.achievements",
            rootViewModel: rootViewModel,
            present: { GameCenterDashboard.presentAchievements() }
        )
    }

    /// `Leaderboards` — a11y id `game.progress.leaderboards`.
    public static func leaderboards(rootViewModel: GameRootViewModel<Route>) -> GameCenterEntryRow<Route> {
        GameCenterEntryRow(
            title: String(localized: "Leaderboards", bundle: .main),
            systemImage: "list.number",
            accessibilityIdentifier: "game.progress.leaderboards",
            rootViewModel: rootViewModel,
            present: { GameCenterDashboard.present() }
        )
    }
}
