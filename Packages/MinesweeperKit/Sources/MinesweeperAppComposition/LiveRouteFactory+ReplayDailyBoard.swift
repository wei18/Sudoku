// LiveRouteFactory+ReplayDailyBoard — the `.replayDailyBoard` destination
// (#841).
//
// Split into its own file purely to keep LiveRouteFactory.swift under the
// 400-line `file_length` lint ceiling (same rationale as `+Stats.swift` /
// `+Helpers.swift`) — this is the same route table, not a separate concern.
// The factory's stored deps are `private` (file-scoped), so the switch
// passes them in rather than the extension reading them.
//
// #841 ("daily retry after loss generates a different board per first click
// — daily must be one fixed game"): a bare `MinesweeperBoardView(difficulty:
// seed:)` re-derives mine placement from THIS replay's own first click (the
// engine's deferred/first-click-salted path), so a different tap on each
// retry silently produced a different board. Routed through
// `MinesweeperDailyReplayLoaderView` instead, which fetches the daily's own
// persisted "failed" record (written by the ORIGINAL first-ever attempt on
// loss) and replays with that exact mine layout. Falls back to the old
// direct-inline construction when no `savedGameStore` is wired
// (preview/test callsites) — byte-identical to pre-#841 behavior there.

internal import SwiftUI
internal import GameAppKit
internal import GameAudio
internal import MinesweeperEngine
internal import MinesweeperPersistence
internal import MinesweeperUI
internal import MonetizationCore
internal import Telemetry

extension LiveRouteFactory {
    @MainActor
    // Unlabeled leading params mirror `statsDestination`'s convention — keeps
    // the switch case's call to a handful of lines under the caller file's
    // 400-line ceiling.
    static func replayDailyBoardDestination(
        _ route: AppRoute,
        _ path: Binding<[AppRoute]>?,
        _ difficulty: Difficulty,
        _ seed: UInt64,
        adProvider: (any AdProvider)?,
        adGate: AdGate?,
        errorReporter: (any ErrorReporter)?,
        soundPlayer: (any SoundPlaying)?,
        savedGameStore: MinesweeperSavedGameStore?,
        onPresentBoard: (@MainActor (AppRoute) -> Void)?
    ) -> AnyView {
        boardDestination(
            route: route,
            path: path,
            onPresentBoard: onPresentBoard
        ) {
            guard let savedGameStore else {
                return AnyView(
                    MinesweeperBoardView(
                        difficulty: difficulty,
                        seed: seed,
                        mode: .practice,
                        adProvider: adProvider,
                        adGate: adGate,
                        gameCenter: nil,
                        errorReporter: errorReporter,
                        soundPlayer: soundPlayer ?? NoopSoundPlaying()
                        // store: nil, recordName: nil, personalRecordStore: nil
                        // — see the #841 header comment above + the original
                        // Epic 8 rationale: no save/GC/personal-record
                        // side-effects from an unscored replay.
                    )
                )
            }
            return AnyView(
                MinesweeperDailyReplayLoaderView(
                    difficulty: difficulty,
                    seed: seed,
                    // Same identity as the daily's real record — the one
                    // `.board(mode: .daily)` writes to on loss.
                    recordName: MinesweeperSavedGameStore.recordName(mode: .daily, difficulty: difficulty),
                    store: savedGameStore,
                    adProvider: adProvider,
                    adGate: adGate,
                    errorReporter: errorReporter,
                    soundPlayer: soundPlayer ?? NoopSoundPlaying()
                )
            )
        }
    }
}
