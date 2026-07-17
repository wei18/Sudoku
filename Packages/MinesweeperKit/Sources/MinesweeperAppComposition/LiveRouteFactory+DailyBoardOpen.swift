// LiveRouteFactory+DailyBoardOpen — the `.board(mode: .daily / .practice)`
// destination (#842).
//
// Split into its own file purely to keep LiveRouteFactory.swift under the
// 400-line `file_length` lint ceiling (same rationale as `+ReplayDailyBoard.swift`
// / `+Stats.swift` / `+Helpers.swift`) — this is the same route table, not a
// separate concern. The factory's stored deps are `private` (file-scoped), so
// the switch passes them in rather than this extension reading them — mirrors
// `replayDailyBoardDestination`'s exact shape.
//
// #842 ("daily hub tap races phase-2's completion/failure overlay fetch"): a
// fast tap on a card whose REAL daily state is already completed or failed —
// still `false`/`false` on the tapped `MinesweeperDailyCard` because
// `fillCompletionAndFailureOverlay` (phase 2) hasn't landed yet, #530/#774 —
// used to push this SAME `.board(mode: .daily)` route regardless. A loss then
// re-derives mine placement from THIS attempt's own first click (#841's
// deferred/first-click-salted path) and OVERWRITES the real Failed record
// with a different layout; a win double-submits a GC score. Fix: when
// `mode == .daily` AND a `savedGameStore` is wired (production), wrap the
// mount in `MinesweeperDailyOpenGuardView`, which re-queries the store's
// truth for TODAY before ever mounting a playable board — see that view's
// header comment for the full tri-state (completed / failed / playable /
// honest-failure) rationale. Practice (never re-verified — a fresh board
// every tap) and the no-store preview/test callsite both fall straight
// through to the direct `MinesweeperBoardView` construction below,
// byte-identical to pre-#842 behavior there.

internal import SwiftUI
internal import GameCenterClient
internal import GameAppKit
internal import MinesweeperUI
internal import MinesweeperEngine
internal import MinesweeperPersistence
internal import GameAudio
internal import MonetizationCore
internal import Telemetry
internal import SettingsUI

extension LiveRouteFactory {
    // Unlabeled leading params mirror `replayDailyBoardDestination`'s /
    // `statsDestination`'s convention — keeps the switch case's call to a
    // handful of lines under the caller file's 400-line ceiling.
    @MainActor
    static func boardOpenDestination(
        _ route: AppRoute,
        _ path: Binding<[AppRoute]>?,
        _ difficulty: Difficulty,
        _ seed: UInt64,
        _ mode: GameMode,
        adProvider: (any AdProvider)?,
        adGate: AdGate?,
        gameCenter: (any GameCenterClient)?,
        errorReporter: (any ErrorReporter)?,
        soundPlayer: (any SoundPlaying)?,
        makeDailyReminderPrimer: (@MainActor () -> ReminderPrimerCoordinator)?,
        savedGameStore: MinesweeperSavedGameStore?,
        personalRecordStore: MinesweeperPersonalRecordStore?,
        onPresentBoard: (@MainActor (AppRoute) -> Void)?
    ) -> AnyView {
        boardDestination(
            route: route,
            path: path,
            onPresentBoard: onPresentBoard
        ) {
            if mode == .daily, let savedGameStore {
                return AnyView(
                    MinesweeperDailyOpenGuardView(
                        difficulty: difficulty,
                        seed: seed,
                        store: savedGameStore,
                        adProvider: adProvider,
                        adGate: adGate,
                        gameCenter: gameCenter,
                        errorReporter: errorReporter,
                        soundPlayer: soundPlayer ?? NoopSoundPlaying(),
                        makeDailyReminderPrimer: makeDailyReminderPrimer,
                        personalRecordStore: personalRecordStore,
                        // #842 round 2 (low finding): dual-context Close —
                        // see MinesweeperDailyOpenGuardView.exitToHub's doc.
                        path: path
                    )
                )
            }
            return AnyView(
                MinesweeperBoardView(
                    difficulty: difficulty,
                    seed: seed,
                    mode: mode,
                    adProvider: adProvider,
                    adGate: adGate,
                    gameCenter: gameCenter,
                    errorReporter: errorReporter,
                    // #330 P2: gameplay audio. nil (preview / test) → silent Noop.
                    soundPlayer: soundPlayer ?? NoopSoundPlaying(),
                    // #652: Play Again — dismiss current board and present a new
                    // practice board at the same difficulty with a fresh seed.
                    // Only wired when `onPresentBoard` is available AND this is a
                    // practice board: a daily is one-per-day, so Play Again would
                    // silently hand back a practice board (it draws mode: .practice).
                    onPlayAgain: mode == .practice
                        ? onPresentBoard.map { presenter in
                            { @MainActor difficulty in
                                let seed = UInt64.random(in: .min ... .max)
                                presenter(.board(difficulty: difficulty, seed: seed, mode: .practice))
                            }
                        }
                        : nil,
                    // #455 step 4: persistence seam. The save's identity is
                    // derived ONCE here (today's date for a daily, a singleton
                    // slot per practice difficulty) — see the store's
                    // recordName helpers for the scheme rationale.
                    // #814: Daily-win reminder primer — the board's own
                    // gate keeps it nil on loss / practice.
                    makeDailyReminderPrimer: makeDailyReminderPrimer,
                    store: savedGameStore,
                    recordName: MinesweeperSavedGameStore.recordName(mode: mode, difficulty: difficulty),
                    personalRecordStore: personalRecordStore
                )
            )
        }
    }
}
