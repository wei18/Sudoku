// AchievementsRow — the Progress tab's Game Center entry point (#1020, C-36).
//
// design.md §9.4 pairs two contract changes: the HOME screen's Leaderboard card
// disappears with HOME (C-35, BREAK) and the Progress tab gains this row
// (C-36, NEW). Together with the Settings Game Center row they are the app's
// two remaining GC entry points, both in menu-screen contexts (HIG: put the
// access point in menu screens).
//
// Both route through `GameRootViewModel.presentGameCenterOrAlert`, the single
// auth gate #685 established — a signed-out tap raises the shared alert instead
// of silently no-op'ing.
//
// Terminology is HIG-mandated: Apple's feature is called **Achievements**.
// Never "Trophies" / "Awards" / "Medals".
//
// Stage B (#1020 app migration) places this row inside each app's Progress
// (statistics) screen; it lives in GameAppKit rather than either app's Kit
// because both games present the identical row (mirror principle).

public import SwiftUI
public import GameCenterClient
internal import GameShellUI

@MainActor
public struct AchievementsRow<Route: Hashable & Sendable>: View {
    private let rootViewModel: GameRootViewModel<Route>

    /// The presentation side effect, injected so a test can observe it without
    /// standing up GameKit. Defaults to the shared native dashboard — the same
    /// call the retired HOME leaderboard card made.
    private let present: @MainActor () -> Void

    @Environment(\.theme) private var theme

    public init(
        rootViewModel: GameRootViewModel<Route>,
        present: @escaping @MainActor () -> Void = { GameCenterDashboard.present() }
    ) {
        self.rootViewModel = rootViewModel
        self.present = present
    }

    public var body: some View {
        Button(action: activate) {
            HStack(spacing: 12) {
                Image(systemName: "trophy")
                    .foregroundStyle(theme.accent.primary.resolved)
                Text("Achievements")
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.text.primary.resolved)
                Spacer()
                // Outward-jump glyph, not a chevron: this presents Apple's
                // system dashboard as a side effect rather than pushing an
                // in-app destination — the same distinction the retired
                // `HomeMode.trailingSymbolName` drew for Leaderboard.
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
        .accessibilityIdentifier("game.progress.achievements")
    }

    /// The row's tap behavior, factored out of the `Button` so the C-36
    /// contract (authenticated → present; signed out → alert, no present) is
    /// unit-testable without rendering.
    func activate() {
        rootViewModel.presentGameCenterOrAlert(present: present)
    }
}
