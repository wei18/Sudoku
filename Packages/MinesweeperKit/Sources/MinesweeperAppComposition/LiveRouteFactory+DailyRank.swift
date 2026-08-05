// LiveRouteFactory+DailyRank — the `.dailyRank` destination (#983).
//
// Split into its own file for the same reason as `LiveRouteFactory+Stats.swift`
// — keeps `LiveRouteFactory.swift` under the 400-line `file_length` ceiling.
//
// The shared `GameAppKit.DailyRankView`. Tabs reuse the SAME localized
// difficulty names Practice already renders (`MinesweeperPracticeHubView`'s
// `displayName(_:)` switch: "Beginner"/"Intermediate"/"Expert") — no new
// difficulty-name strings — and the SAME leaderboard ids Completion submits
// to (`MinesweeperLeaderboardID.daily(for:)`).

public import SwiftUI
public import GameCenterClient
public import GameAppKit
internal import MinesweeperUI
internal import MinesweeperEngine

extension LiveRouteFactory {
    @MainActor
    // Unlabeled params: the single call site (the `.dailyRank` switch case)
    // keeps to one line under the caller file's 400-line `file_length` ceiling.
    static func dailyRankDestination(
        _ gameCenter: (any GameCenterClient)?,
        _ currentAuthState: (@MainActor () -> GameCenterAuthState)?
    ) -> AnyView {
        // `gameCenter` is optional only for preview/test callsites that don't
        // wire GC (production `GameDeps.gameCenter` is always non-nil) — the
        // route degrades to an empty screen rather than force-unwrapping.
        guard let gameCenter else { return AnyView(EmptyView()) }
        return AnyView(
            DailyRankView(
                viewModel: DailyRankViewModel(
                    gameCenter: gameCenter,
                    tabs: Difficulty.allCases.map { difficulty in
                        DailyRankTab(
                            id: difficulty.rawValue,
                            titleKey: displayName(difficulty),
                            leaderboardId: MinesweeperLeaderboardID.daily(for: difficulty)
                        )
                    },
                    initialAuthState: currentAuthState?() ?? .unknown
                )
            )
        )
    }

    /// Mirrors `MinesweeperPracticeHubView.displayName(_:)` exactly — the
    /// leaderboard id segment reuses Sudoku's easy/medium/hard naming
    /// (`MinesweeperLeaderboardID`'s doc comment), so an explicit switch
    /// (not `.rawValue.capitalized`) is required to show the correct
    /// Beginner/Intermediate/Expert catalog keys.
    private static func displayName(_ difficulty: Difficulty) -> LocalizedStringKey {
        switch difficulty {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .expert: return "Expert"
        }
    }
}
