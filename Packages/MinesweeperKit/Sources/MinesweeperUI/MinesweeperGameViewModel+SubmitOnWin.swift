// MinesweeperGameViewModel+SubmitOnWin — Game Center + personal-record
// submit-on-win (#291, #329, #699, #705).
//
// Split into its own file (not the main class body) purely to keep
// MinesweeperGameViewModel.swift under the 400-line `file_length` lint
// ceiling — this extension is not a separate concern, it's the same
// "what happens on a win" logic as the properties it reads (`gameCenter`,
// `didSubmitWin`, `didAttemptAuth` are `internal`, not `private`,
// specifically so this file can see them).

public import GameCenterClient
public import MinesweeperPersistence
public import Telemetry

extension MinesweeperGameViewModel {

    /// Submit the elapsed time to this difficulty's recurring daily leaderboard
    /// (daily-mode only), and record the personal best (#699/#705, both modes)
    /// the first time a board reaches `.won`.
    ///
    /// The two writes have DIFFERENT mode gates:
    /// - Game Center: `mode == .daily` only — practice wins must never submit
    ///   (#329, mirrors Sudoku's `GameCenterSink` gate) — permanent.
    /// - Personal best: daily AND practice (#705 widened the #699 daily-only
    ///   launch scope, matching Sudoku). The dedup puzzleId differs by mode —
    ///   see the `puzzleId` derivation below.
    ///
    /// Both writes are best-effort: a `nil` seam is a no-op, and any thrown
    /// error is funneled (never re-raised) so neither can interrupt the win
    /// moment. The `didSubmitWin` latch now guards both writes together (it
    /// used to gate on `mode == .daily` before latching, so a practice win
    /// never latched it — that's fine now that practice writes are eligible
    /// too: a re-entrant refresh over the same win must still fire each write
    /// at most once).
    func submitWinIfWon() async {
        guard snapshot.status == .won, !didSubmitWin else { return }
        // Latch before the await so a re-entrant refresh tick can't double-fire.
        didSubmitWin = true

        let difficulty = session.difficulty
        let elapsed = snapshot.elapsedSeconds

        if mode == .daily, let gameCenter {
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
                    source: "MinesweeperGameViewModel.submitWin"
                )
            }
        }

        if let personalRecordStore {
            let puzzleId: String
            switch mode {
            case .daily:
                // The board's own CloudKit identity is the dedup key (mirrors
                // Sudoku's puzzleId); fallback covers callsites without `recordName`.
                puzzleId = recordName ?? MinesweeperSavedGameStore.recordName(mode: mode, difficulty: difficulty)
            case .practice:
                // #705: `recordName` here is the singleton practice save slot
                // (`practice-{difficulty}`) and would collapse every practice
                // win into one dedup entry — use the per-game generation seed
                // instead (see MinesweeperPracticeIdentity's doc comment).
                puzzleId = MinesweeperPracticeIdentity.puzzleId(seed: snapshot.seed, difficulty: difficulty)
            }
            do {
                try await personalRecordStore.recordCompletion(
                    puzzleId: puzzleId, modeRaw: mode.rawValue, difficulty: difficulty, elapsedSeconds: elapsed
                )
            } catch {
                await errorReporter?.report(
                    UserFacingError.classify(error),
                    underlying: error,
                    source: "MinesweeperGameViewModel.submitWin.personalRecord"
                )
            }
        }
    }
}
