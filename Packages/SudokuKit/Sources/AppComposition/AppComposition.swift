// AppComposition — DI composition root (design.md §How.1).
//
// Three factory methods produce a fully-wired `AppComposition` for the
// three environments the App needs to run in:
//
//   - `.live()`    — CloudKit / GameKit / OSLog production wiring.
//   - `.preview()` — SwiftUI Preview fakes (no IO).
//   - `.tests()`   — Unit / snapshot test fakes (no IO).
//
// The App target depends only on this product; `SudokuApp.body` reads
// `composition.rootViewModel` and hands it to `RootView`.
//
// `gameViewModelFactory` is intentionally `async throws` — per the Phase 8
// Part 2 forecast, the live GameViewModel needs a snapshot from
// `Persistence.loadOrCreate(...)` BEFORE construction. Tests / previews
// can supply the same factory without IO via the snapshot init.

internal import Foundation
internal import GameCenterClient
internal import GameState
internal import Persistence
public import PuzzleStore
internal import SudokuEngine
public import SudokuUI
internal import Telemetry

@MainActor
public struct AppComposition {
    public let rootViewModel: RootViewModel
    public let dailyHubViewModelFactory: @MainActor () -> DailyHubViewModel
    public let practiceHubViewModelFactory: @MainActor () -> PracticeHubViewModel
    public let gameViewModelFactory: (PuzzleEnvelope) async throws -> GameViewModel
    public let completionViewModelFactory: @MainActor (_ puzzleId: String, _ elapsedSeconds: Int) -> CompletionViewModel
    public let leaderboardViewModelFactory: @MainActor (_ leaderboardId: String) -> LeaderboardViewModel
    public let settingsViewModelFactory: @MainActor () -> SettingsViewModel

    public init(
        rootViewModel: RootViewModel,
        dailyHubViewModelFactory: @escaping @MainActor () -> DailyHubViewModel,
        practiceHubViewModelFactory: @escaping @MainActor () -> PracticeHubViewModel,
        gameViewModelFactory: @escaping (PuzzleEnvelope) async throws -> GameViewModel,
        completionViewModelFactory: @escaping @MainActor (String, Int) -> CompletionViewModel,
        leaderboardViewModelFactory: @escaping @MainActor (String) -> LeaderboardViewModel,
        settingsViewModelFactory: @escaping @MainActor () -> SettingsViewModel
    ) {
        self.rootViewModel = rootViewModel
        self.dailyHubViewModelFactory = dailyHubViewModelFactory
        self.practiceHubViewModelFactory = practiceHubViewModelFactory
        self.gameViewModelFactory = gameViewModelFactory
        self.completionViewModelFactory = completionViewModelFactory
        self.leaderboardViewModelFactory = leaderboardViewModelFactory
        self.settingsViewModelFactory = settingsViewModelFactory
    }
}
