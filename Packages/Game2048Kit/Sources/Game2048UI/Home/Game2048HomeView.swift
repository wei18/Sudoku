// Game2048HomeView — Tiles2048 Home stub (SDD-004 Milestone 2).
//
// Adopts the shared `HomeScreen` scaffold from GameShellKit. Milestone 3
// will wire real subtitles from the app's Localizable.xcstrings, the
// ResumePill via GameAppKit, the banner slot via AppMonetizationKit, and
// the Game Center leaderboard action.
//
// Mode-card taps push placeholder routes into the navigation stack; the
// real RouteFactory destination views land in Milestone 3.

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
                    // M3: replace with localized subtitle from Localizable.xcstrings.
                    subtitleKey: "Today's seeded board",
                    onTap: onDailyTap
                ),
                HomeModeItem(
                    mode: .practice,
                    // M3: replace with localized subtitle from Localizable.xcstrings.
                    subtitleKey: "Unlimited classic play",
                    onTap: onPracticeTap
                ),
                HomeModeItem(
                    mode: .leaderboard,
                    // M3: wire real Game Center dashboard action (#291 pattern).
                    subtitleKey: "Top daily scores",
                    onTap: { /* M3: gameCenter.presentDashboard() */ }
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
