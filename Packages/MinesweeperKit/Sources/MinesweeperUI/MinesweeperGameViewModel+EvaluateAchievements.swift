// MinesweeperGameViewModel+EvaluateAchievements — Game Center achievement
// evaluation + reporting on win (#700).
//
// Mounted beside `submitDailyTimeIfWon()` (same file-split rationale: keeps
// the main class body under the 400-line lint ceiling) but as its OWN latch
// (`didEvaluateAchievements`), because most MS achievements are NOT
// daily-gated (First Sweep / volume / No Flags / Expert / Lightning apply to
// both modes) — reusing `submitDailyTimeIfWon`'s daily-only early-return
// would silently drop every practice-mode achievement.
//
// Best-effort throughout: a `nil` seam is a no-op, and any thrown error is
// funneled (never re-raised) so achievement bookkeeping can never interrupt
// the win moment — same posture as `submitDailyTimeIfWon()`.

public import Foundation
public import GameCenterClient
public import MinesweeperEngine
public import MinesweeperPersistence
public import Telemetry

extension MinesweeperGameViewModel {

    /// Evaluate + report the 11 MS achievements when a board (any mode)
    /// reaches `.won`. Single call site: the live win transition in
    /// `reveal()` (NOT `refresh()` — unlike `submitDailyTimeIfWon()` this is
    /// not idempotent: it increments the cumulative win tally, and a refresh
    /// over an already-won board must not inflate it). Invoked right after
    /// `submitDailyTimeIfWon()` so the daily personal-best write for THIS win
    /// has already landed before the full-spectrum / streak facts are
    /// gathered below.
    func evaluateAchievementsIfWon() async {
        guard snapshot.status == .won, !didEvaluateAchievements else { return }
        didEvaluateAchievements = true

        // The local tally is a device fact, not a Game Center fact — it must
        // advance even when no GC seam is threaded (offline/signed-out play
        // still counts toward the volume achievements on the next report).
        let cumulativeWinCount = winCountStore.incrementAndGet()

        guard let gameCenter else { return }

        let difficulty = session.difficulty

        var dailyWinDifficulties: Set<Difficulty> = []
        var consecutiveDailyStreak = 0
        if mode == .daily, let personalRecordStore {
            do {
                var dailyWinDays: Set<String> = []
                for candidate in Difficulty.allCases {
                    let record = try await personalRecordStore.fetch(modeRaw: mode.rawValue, difficulty: candidate)
                    if !record.completedPuzzleIds.isEmpty {
                        dailyWinDifficulties.insert(candidate)
                    }
                    for puzzleId in record.completedPuzzleIds {
                        if let day = MinesweeperSavedGameStore.dailyDay(fromRecordName: puzzleId) {
                            dailyWinDays.insert(day)
                        }
                    }
                }
                consecutiveDailyStreak = MinesweeperDailyStreakMath.consecutiveStreak(
                    dailyWinDays: dailyWinDays, endingOn: Date()
                )
            } catch {
                await errorReporter?.report(
                    UserFacingError.classify(error),
                    underlying: error,
                    source: "MinesweeperGameViewModel.evaluateAchievementsIfWon.dailyFacts"
                )
            }
        }

        let fact = MinesweeperWinFact(
            mode: mode,
            difficulty: difficulty,
            elapsedSeconds: snapshot.elapsedSeconds,
            // Session-tracked, snapshot-persisted fact (#700 CR): survives
            // save/resume, unlike a ViewModel-instance latch would.
            flagsPlaced: snapshot.everFlagged ? 1 : 0,
            cumulativeWinCount: cumulativeWinCount,
            dailyWinDifficulties: dailyWinDifficulties,
            consecutiveDailyStreak: consecutiveDailyStreak
        )

        for progress in MinesweeperAchievementEvaluator.evaluate(for: fact) {
            let prefixed = AchievementProgress(
                achievementId: MinesweeperAchievementID.prefix + progress.achievementId,
                percentComplete: progress.percentComplete
            )
            do {
                try await gameCenter.reportAchievement(prefixed)
            } catch {
                await errorReporter?.report(
                    UserFacingError.classify(error),
                    underlying: error,
                    source: "MinesweeperGameViewModel.evaluateAchievementsIfWon.reportAchievement"
                )
            }
        }
    }
}
