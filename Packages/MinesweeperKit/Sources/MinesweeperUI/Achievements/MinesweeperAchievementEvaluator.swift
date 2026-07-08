// MinesweeperAchievementEvaluator — computes the 11 MS achievements
// (issue #700, owner-approved 2026-07-06) from a `MinesweeperWinFact`.
//
// Unlike Sudoku's `AchievementEvaluator` (an actor that re-derives state from
// Persistence on every completion), this evaluator is a pure, synchronous
// function: the ViewModel call site does the IO (personal-best fetches, the
// local win-count tally) and hands the result in as a value. This keeps every
// achievement rule unit-testable with a plain struct literal — no fake
// CloudKit gateway needed.
//
// Every achievement here is idempotent-safe to re-report: GameKit itself
// dedupes an already-100%-earned achievement, so a boolean achievement (e.g.
// "First Sweep") reports 100% on every qualifying win, not just the first —
// mirroring Sudoku's `AchievementEvaluator` idiom (e.g. `expert_solver` fires
// on every Hard completion, not just the first).

public import GameCenterClient
public import MinesweeperEngine

public enum MinesweeperAchievementEvaluator {

    /// Expert win under this many seconds qualifies for "Lightning Sweep".
    private static let lightningSweepThresholdSeconds = 180

    /// Evaluate all 11 achievements for the just-completed win described by `fact`.
    public static func evaluate(for fact: MinesweeperWinFact) -> [AchievementProgress] {
        var results: [AchievementProgress] = []

        // Starter
        results.append(AchievementProgress(achievementId: MinesweeperAchievementID.firstSweep, percentComplete: 100))
        if fact.mode == .daily {
            results.append(AchievementProgress(achievementId: MinesweeperAchievementID.dailyDebut, percentComplete: 100))
        }

        // Volume — progressive, both modes combined.
        results.append(progress(MinesweeperAchievementID.winsComplete10, fact.cumulativeWinCount, target: 10))
        results.append(progress(MinesweeperAchievementID.winsComplete50, fact.cumulativeWinCount, target: 50))
        results.append(progress(MinesweeperAchievementID.winsComplete200, fact.cumulativeWinCount, target: 200))

        // Difficulty
        if fact.difficulty == .expert {
            results.append(AchievementProgress(achievementId: MinesweeperAchievementID.expertFirstWin, percentComplete: 100))
        }
        if fact.mode == .daily, Set(Difficulty.allCases).isSubset(of: fact.dailyWinDifficulties) {
            results.append(AchievementProgress(achievementId: MinesweeperAchievementID.dailyFullSpectrum, percentComplete: 100))
        }

        // Skill
        if fact.flagsPlaced == 0 {
            results.append(AchievementProgress(achievementId: MinesweeperAchievementID.skillNoFlags, percentComplete: 100))
        }
        if fact.difficulty == .expert, fact.elapsedSeconds < lightningSweepThresholdSeconds {
            results.append(AchievementProgress(achievementId: MinesweeperAchievementID.skillLightningExpert, percentComplete: 100))
        }

        // Streak — daily only.
        if fact.mode == .daily {
            if fact.consecutiveDailyStreak >= 7 {
                results.append(AchievementProgress(achievementId: MinesweeperAchievementID.dailyStreak7, percentComplete: 100))
            }
            if fact.consecutiveDailyStreak >= 30 {
                results.append(AchievementProgress(achievementId: MinesweeperAchievementID.dailyStreak30, percentComplete: 100))
            }
        }

        return results
    }

    private static func progress(_ shortId: String, _ count: Int, target: Int) -> AchievementProgress {
        guard target > 0 else { return AchievementProgress(achievementId: shortId, percentComplete: 0) }
        let raw = Double(count) / Double(target) * 100.0
        return AchievementProgress(achievementId: shortId, percentComplete: min(100.0, max(0.0, raw)))
    }
}
