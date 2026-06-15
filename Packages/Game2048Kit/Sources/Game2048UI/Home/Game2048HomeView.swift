// Game2048HomeView — Tiles2048 home screen.
//
// Adopts the shared `HomeScreen` scaffold from GameShellKit. Tapping Daily or
// Classic fires the injected callback; Game2048Root converts these into
// `.board(seed:mode:)` route pushes.
//
// M4 will add: ResumePill via GameAppKit, banner slot via AppMonetizationKit,
// real Game Center leaderboard action, and Game2048Theme injection.

public import SwiftUI
internal import GameShellUI

@MainActor
public struct Game2048HomeView: View {
    private let onDailyTap: @MainActor () -> Void
    private let onPracticeTap: @MainActor () -> Void
    private let onSettingsTap: @MainActor () -> Void

    public init(
        onDailyTap: @escaping @MainActor () -> Void,
        onPracticeTap: @escaping @MainActor () -> Void,
        onSettingsTap: @escaping @MainActor () -> Void
    ) {
        self.onDailyTap = onDailyTap
        self.onPracticeTap = onPracticeTap
        self.onSettingsTap = onSettingsTap
    }

    public var body: some View {
        HomeScreen(
            items: [
                HomeModeItem(
                    mode: .daily,
                    subtitleKey: "Today's seeded board",
                    onTap: onDailyTap
                ),
                HomeModeItem(
                    mode: .practice,
                    subtitleKey: "Unlimited classic play",
                    onTap: onPracticeTap
                ),
                HomeModeItem(
                    mode: .leaderboard,
                    // M4: wire real Game Center dashboard action (#291 pattern).
                    subtitleKey: "Top daily scores",
                    onTap: { /* M4: gameCenter.presentDashboard() */ }
                ),
                HomeModeItem(
                    mode: .settings,
                    subtitleKey: "Preferences",
                    onTap: onSettingsTap
                ),
            ]
        )
        .navigationTitle("2048 Tiles")
    }
}
