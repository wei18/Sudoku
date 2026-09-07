// Live+TabRoots — Minesweeper's per-tab root content for `GameConfig.makeTabRoot`
// (#1020, design.md §2.1). Extracted from Live.swift to keep that file readable
// (mirrors SudokuKit's `Live+TabRoots.swift`).
//
// `.today` / `.practice` / `.progress` replace the retired `.daily` /
// `.practice` / `.stats` ROUTES — these are now the three permanent tabs, so
// their content is built once per launch by `makeGameApp`'s
// `memoizedTabRoots` (see `MakeGameApp+Helpers.swift`), not re-constructed
// per navigation like a pushed destination. `makeTabRoot` below is therefore
// a plain static function taking exactly the deps each tab's content needs —
// not the whole `GameDeps` bag — so it stays unit-testable with lightweight
// fakes (mirrors `LiveRouteFactoryTests`), without having to fabricate the
// unrelated fields (audio, reminders, monetization…) a full `GameDeps` would
// require.

internal import SwiftUI
internal import GameAppKit
internal import GameShellUI
internal import MonetizationCore
internal import Persistence
internal import MinesweeperPersistence
internal import MinesweeperUI
internal import Telemetry
internal import MinesweeperEngine

extension MinesweeperAppComposition {

    /// `GameConfig.makeTabRoot` closure body for Minesweeper, called once per
    /// tab at composition time (see the file header + `MakeGameApp+Helpers
    /// .swift`'s `memoizedTabRoots` contract — hub view models are built HERE,
    /// never inside a view body).
    @MainActor
    static func makeTabRoot(
        tab: AppTab,
        persistence: any PersistenceProtocol,
        errorReporter: any ErrorReporter,
        telemetry: Telemetry,
        adProvider: any AdProvider,
        adGate: AdGate,
        savedGameStore: MinesweeperSavedGameStore,
        dailyOverlayReading: (any MinesweeperDailyOverlayReading)?,
        personalRecordStore: MinesweeperPersonalRecordStore,
        rootViewModel: GameRootViewModel<AppRoute>
    ) -> AnyView {
        switch tab {
        case .today:
            // #290: date-seeded daily trio + completion overlay. The hub VM
            // pulls the three boards from `LiveMinesweeperDailyProvider`
            // (pure, deterministic per UTC day) and marks completed/failed
            // cards via `MinesweeperSavedGameStore.fetchCompletedDailyIds` /
            // `fetchFailedDailyIds` (Epic 8 / SDD-003; #816 moved completed
            // off the `puzzleId`-assuming `PersistenceProtocol` query).
            // #1020 CR: no `banner:` here — `TodayTabHost` (GameAppKit) already
            // wraps this content with its OWN `BannerSlotView` (and is the C-33
            // ATT anchor); passing another one too would render two banners.
            // `MinesweeperDailyHubView`'s `banner:` param defaults to `EmptyView()`.
            return AnyView(
                MinesweeperDailyHubView(
                    viewModel: MinesweeperDailyHubViewModel(
                        path: rootViewModel.pathBinding(for: .today),
                        provider: LiveMinesweeperDailyProvider(),
                        persistence: persistence,
                        // #935 batch 3: `dailyOverlayReading` (when the composition
                        // root wired one — the E2E fake-or-live resolution) takes
                        // priority; otherwise fall back to the concrete
                        // `savedGameStore`, which already conforms.
                        savedGameStore: dailyOverlayReading ?? savedGameStore,
                        personalRecordStore: personalRecordStore,
                        errorReporter: errorReporter
                    )
                )
            )
        case .practice:
            // #720 G2: remember the player's last-picked Practice difficulty
            // across launches instead of always resetting to Beginner.
            let difficultyStore = LastSelectionStore(
                key: "com.wei18.minesweeper.practice.lastDifficulty",
                fallback: Difficulty.beginner.rawValue
            )
            return AnyView(
                MinesweeperPracticeHubView(
                    path: rootViewModel.pathBinding(for: .practice),
                    initialDifficulty: Difficulty(rawValue: difficultyStore.load()) ?? .beginner,
                    onDifficultyChanged: { difficultyStore.save($0.rawValue) },
                    banner: { LiveRouteFactory.bannerSlot(adProvider: adProvider, adGate: adGate) }
                )
            )
        case .progress:
            // #1021 Phase D: the shared `ProgressScreen` (GameAppKit) —
            // personal bests + a month streak calendar + the native
            // `Achievements`/`Leaderboards` Game Center entry points.
            // #1021 Phase E2: the retired Statistics screen this replaced is
            // now fully deleted (its "01-home" ASC store-screenshot slot in
            // `mise-tasks/store/screenshots` was repointed at `ProgressScreen`'s
            // own store fixture — see `ProgressScreenTests.swift`).
            //
            // #935 batch 3: `dailyOverlayReading` (when the composition root
            // wired one — the E2E fake-or-live resolution) takes priority;
            // otherwise fall back to the concrete `savedGameStore` — same
            // precedent as the `.today` case above.
            return AnyView(
                MinesweeperProgressHostView(
                    viewModel: MinesweeperProgressViewModel(
                        store: personalRecordStore,
                        completionSource: dailyOverlayReading ?? savedGameStore,
                        errorReporter: errorReporter,
                        telemetry: telemetry
                    ),
                    rootViewModel: rootViewModel
                )
            )
        }
    }
}
