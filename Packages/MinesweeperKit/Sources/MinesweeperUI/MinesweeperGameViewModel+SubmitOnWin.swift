// MinesweeperGameViewModel+SubmitOnWin — Game Center + personal-record
// submit-on-win (#291, #329, #699).
//
// Split into its own file (not the main class body) purely to keep
// MinesweeperGameViewModel.swift under the 400-line `file_length` lint
// ceiling — this extension is not a separate concern, it's the same
// "what happens on a daily win" logic as the properties it reads
// (`gameCenter`, `didSubmitWin`, `didAttemptAuth` are `internal`, not
// `private`, specifically so this file can see them).

public import GameCenterClient
public import MinesweeperPersistence
public import Telemetry

extension MinesweeperGameViewModel {

    /// Submit the elapsed time to this difficulty's recurring daily leaderboard,
    /// and record the personal best (#699), the first time a **daily-mode**
    /// board reaches `.won`.
    ///
    /// The `mode == .daily` gate covers two DIFFERENT contracts:
    /// - Game Center: practice wins must never submit (#329, mirrors Sudoku's
    ///   `GameCenterSink` gate) — permanent.
    /// - Personal best: daily-only is the INITIAL scope, a deliberate
    ///   divergence from Sudoku (which records practice too). MS practice
    ///   recordNames are singletons (`practice-{difficulty}`) and can't serve
    ///   as the dedup puzzleId; widening to practice needs a per-game unique
    ///   id first — tracked in #705.
    ///
    /// Both writes are best-effort: a `nil` seam is a no-op, and any thrown
    /// error is funneled (never re-raised) so neither can interrupt the win
    /// moment.
    func submitDailyTimeIfWon() async {
        guard snapshot.status == .won, !didSubmitWin else { return }
        guard mode == .daily else { return }
        // Latch before the await so a re-entrant refresh tick can't double-fire.
        didSubmitWin = true

        let difficulty = session.difficulty
        let elapsed = snapshot.elapsedSeconds

        if let gameCenter {
            // One-shot auth: a player who wins before ever opening the native
            // GC dashboard would otherwise submit while unauthenticated.
            if !didAttemptAuth {
                didAttemptAuth = true
                _ = try? await gameCenter.authenticate()
            }
            do {
                try await gameCenter.submitScore(
                    leaderboardId: MinesweeperLeaderboardID.daily(for: difficulty),
                    elapsedSeconds: elapsed
                )
            } catch {
                await errorReporter?.report(
                    UserFacingError.classify(error),
                    underlying: error,
                    source: "MinesweeperGameViewModel.submitDailyTime"
                )
            }
        }

        if let personalRecordStore {
            // The board's own CloudKit identity is the dedup key (mirrors
            // Sudoku's puzzleId); fallback covers callsites without `recordName`.
            let puzzleId = recordName ?? MinesweeperSavedGameStore.recordName(mode: mode, difficulty: difficulty)
            do {
                try await personalRecordStore.recordCompletion(
                    puzzleId: puzzleId, modeRaw: mode.rawValue, difficulty: difficulty, elapsedSeconds: elapsed
                )
            } catch {
                await errorReporter?.report(
                    UserFacingError.classify(error),
                    underlying: error,
                    source: "MinesweeperGameViewModel.submitDailyTime.personalRecord"
                )
            }
        }
    }
}
