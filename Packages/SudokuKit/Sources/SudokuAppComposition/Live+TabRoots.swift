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
        rootViewModel: GameRootViewModel<AppRoute>
    ) -> AnyView {
        switch tab {
        case .today:
            // #1024: no `banner:` here — the shared `tabViewBottomAccessory`
            // (design.md §2.4) covers this tab; `TodayTabHost` (GameAppKit)
            // has carried no `BannerSlotView` of its own since that move. The
            // accessory slot's registration is now the "first ad context"
            // that fires the C-33 ATT primer, not a Today-tab-local slot.
            // `DailyHubView`'s `banner:` param is dead (defaults to
            // `EmptyView()`, no caller overrides it) — tracked in #1096.
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
            // #1024: no `banner:` here any more — the shared
            // `tabViewBottomAccessory` (design.md §2.4) covers this tab.
            // #1080: `PracticeHubView`'s `banner:` param and the
            // tab-content-bottom fallback it fed were both removed —
            // obsolete once #1079 confirmed the accessory path.
            return AnyView(
                PracticeHubView(
                    viewModel: PracticeHubViewModel(
                        provider: puzzleProvider,
                        initialDifficulty: Difficulty(rawValue: difficultyStore.load()) ?? .medium,
                        persistDifficulty: { difficultyStore.save($0.rawValue) },
                        path: rootViewModel.pathBinding(for: .practice)
                    )
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
            return AnyView(
                ProgressHostView(
                    viewModel: ProgressViewModel(
                        persistence: persistence,
                        errorReporter: errorReporter,
                        telemetry: telemetry
                    ),
                    rootViewModel: rootViewModel
                )
            )
        }
    }
}
