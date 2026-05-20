// Preview composition — fakes for SwiftUI #Preview.
//
// All factories return deterministic in-memory state. No CloudKit, no
// GameKit, no OSLog. Mirrors `.tests()` semantically; kept as a separate
// entry purely so future Preview-only tweaks (canned snapshots etc.) can
// land without affecting unit/snapshot test behavior.

internal import Foundation
internal import GameCenterClient
internal import GameState
internal import Persistence
internal import PuzzleStore
internal import SudokuEngine
internal import SudokuKitTesting
internal import SudokuUI
internal import Telemetry

extension AppComposition {

    public static func preview() -> AppComposition {
        fakeComposition()
    }

    public static func tests() -> AppComposition {
        fakeComposition()
    }

    internal static func fakeComposition() -> AppComposition {
        let gameCenter = FakeGameCenterClient()
        let persistence = FakePersistence()
        let provider = FakePuzzleProvider()

        let rootViewModel = RootViewModel(
            gameCenter: gameCenter,
            persistence: persistence
        )

        return AppComposition(
            rootViewModel: rootViewModel,
            dailyHubViewModelFactory: {
                DailyHubViewModel(provider: provider, persistence: persistence)
            },
            practiceHubViewModelFactory: {
                PracticeHubViewModel(provider: provider)
            },
            gameViewModelFactory: { envelope in
                // Preview / test path: skip Persistence and feed the
                // envelope's `Puzzle` directly to GameViewModel's snapshot
                // init (no live GameSession, no IO).
                let identity = envelope.identity
                return await MainActor.run {
                    GameViewModel(
                        identity: identity,
                        board: envelope.puzzle.clues
                    )
                }
            },
            completionViewModelFactory: { puzzleId, elapsedSeconds in
                CompletionViewModel(
                    puzzleId: puzzleId,
                    elapsedSeconds: elapsedSeconds,
                    leaderboardId: LeaderboardIDs.id(for: .dailyEasy),
                    gameCenter: gameCenter
                )
            },
            leaderboardViewModelFactory: { leaderboardId in
                LeaderboardViewModel(
                    leaderboardId: leaderboardId,
                    gameCenter: gameCenter
                )
            },
            settingsViewModelFactory: {
                SettingsViewModel(persistence: persistence)
            }
        )
    }
}
