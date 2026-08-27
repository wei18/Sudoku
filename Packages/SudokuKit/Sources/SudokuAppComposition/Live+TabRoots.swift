// Live+TabRoots — Sudoku's per-tab root content for `GameConfig.makeTabRoot`
// (#1020, design.md §2.1). Extracted from Live.swift to keep that file under
// SwiftLint's 400-line ceiling (it already sat at the ceiling before #1020).
//
// `.today` / `.practice` / `.progress` replace the retired `.daily` /
// `.practice` / `.stats` ROUTES — these are now the three permanent tabs, so
// their content is built once per launch by `makeGameApp`'s
// `memoizedTabRoots` (see `MakeGameApp+Helpers.swift`), not re-constructed
// per navigation like a pushed destination. `makeTabRoot` below is therefore
// a plain static function taking exactly the deps each tab's content needs —
// not the whole `GameDeps` bag — so it stays unit-testable with the same
// lightweight Fakes `RouteFactoryTests` already uses, without having to
// fabricate the unrelated fields (audio, reminders, monetization…) a full
// `GameDeps` would require.

internal import SwiftUI
internal import GameAppKit
internal import GameShellUI
internal import MonetizationCore
internal import Persistence
internal import SudokuPersistence
internal import SudokuUI
internal import Telemetry
internal import SudokuEngine

extension SudokuAppComposition {

    /// `GameConfig.makeTabRoot` closure body for Sudoku, called once per tab
    /// at composition time (see the file header + `MakeGameApp+Helpers.swift`'s
    /// `memoizedTabRoots` contract — hub view models are built HERE, never
    /// inside a view body).
    @MainActor
    static func makeTabRoot(
        tab: AppTab,
        puzzleProvider: any PuzzleProviderProtocol,
        persistence: any PersistenceProtocol,
        errorReporter: any ErrorReporter,
        telemetry: Telemetry,
        adProvider: any AdProvider,
        adGate: AdGate,
        rootViewModel: GameRootViewModel<AppRoute>
    ) -> AnyView {
        switch tab {
        case .today:
            // #1020 CR: no `banner:` here — `TodayTabHost` (GameAppKit) already
            // wraps this content with its OWN `BannerSlotView` (and is the C-33
            // ATT anchor); passing another one too would render two banners.
            // `DailyHubView`'s `banner:` param defaults to `EmptyView()`.
            return AnyView(
                DailyHubView(
                    viewModel: DailyHubViewModel(
                        provider: puzzleProvider,
                        persistence: persistence,
                        errorReporter: errorReporter,
                        path: rootViewModel.pathBinding(for: .today),
                        // design.md §3.1: the exhausted block's "Practice" CTA
                        // switches tabs now — it no longer pushes a `.practice`
                        // route (that case no longer exists).
                        selectTab: { rootViewModel.selectedTab = $0 }
                    )
                )
            )
        case .practice:
            // #720 G1: remember the player's last-picked Practice difficulty
            // across launches instead of always resetting to Medium.
            let difficultyStore = LastSelectionStore(
                key: "com.wei18.sudoku.practice.lastDifficulty",
                fallback: Difficulty.medium.rawValue
            )
            return AnyView(
                PracticeHubView(
                    viewModel: PracticeHubViewModel(
                        provider: puzzleProvider,
                        initialDifficulty: Difficulty(rawValue: difficultyStore.load()) ?? .medium,
                        persistDifficulty: { difficultyStore.save($0.rawValue) },
                        path: rootViewModel.pathBinding(for: .practice)
                    ),
                    banner: { LiveRouteFactory.themedBanner(adProvider: adProvider, adGate: adGate) }
                )
            )
        case .progress:
            // #773: Statistics screen — PersonalRecord readout. No banner:
            // the proposal's scope note (§7) explicitly introduces no
            // monetization surface here. #1020 C-36: the Game Center
            // `Achievements` entry point rides the shared `gameCenterSection`
            // slot instead of a bespoke Home leaderboard card.
            return AnyView(
                StatsView(
                    viewModel: StatsViewModel(
                        persistence: persistence,
                        errorReporter: errorReporter,
                        telemetry: telemetry
                    ),
                    gameCenterSection: {
                        AchievementsRow(rootViewModel: rootViewModel)
                    }
                )
            )
        }
    }
}
