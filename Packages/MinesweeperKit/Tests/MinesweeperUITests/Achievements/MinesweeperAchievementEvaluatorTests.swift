// MinesweeperAchievementEvaluatorTests — pure-function coverage for all 11
// MS achievements (#700), including the boundary cases called out in the
// dispatch: progressive percent (9/10, 49/50, 199/200), a broken streak, a
// full-spectrum miss, a flagged win, and the lightning-sweep 179s/181s edge.

import Testing
@testable import MinesweeperUI
import MinesweeperEngine
import GameCenterClient

@Suite("MinesweeperAchievementEvaluator")
struct MinesweeperAchievementEvaluatorTests {

    private func percent(_ results: [AchievementProgress], _ shortId: String) -> Double? {
        results.first { $0.achievementId == shortId }?.percentComplete
    }

    // MARK: - Starter

    @Test("First Sweep reports 100% on any win, any mode")
    func firstSweepAlwaysReports() {
        for mode in GameMode.allCases {
            let fact = MinesweeperWinFact(
                mode: mode, difficulty: .beginner, elapsedSeconds: 60,
                flagsPlaced: 0, cumulativeWinCount: 1
            )
            let results = MinesweeperAchievementEvaluator.evaluate(for: fact)
            #expect(percent(results, MinesweeperAchievementID.firstSweep) == 100)
        }
    }

    @Test("Daily Debut only reports on a daily win")
    func dailyDebutGatedToDailyMode() {
        let daily = MinesweeperWinFact(mode: .daily, difficulty: .beginner, elapsedSeconds: 60, flagsPlaced: 0, cumulativeWinCount: 1)
        let practice = MinesweeperWinFact(mode: .practice, difficulty: .beginner, elapsedSeconds: 60, flagsPlaced: 0, cumulativeWinCount: 1)
        #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: daily), MinesweeperAchievementID.dailyDebut) == 100)
        #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: practice), MinesweeperAchievementID.dailyDebut) == nil)
    }

    // MARK: - Volume (progressive, boundary cases)

    @Test("wins.complete_10 boundary: 9/10 = 90%, 10/10 = 100%")
    func winsComplete10Boundary() {
        let nine = MinesweeperWinFact(mode: .practice, difficulty: .beginner, elapsedSeconds: 60, flagsPlaced: 0, cumulativeWinCount: 9)
        let ten = MinesweeperWinFact(mode: .practice, difficulty: .beginner, elapsedSeconds: 60, flagsPlaced: 0, cumulativeWinCount: 10)
        #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: nine), MinesweeperAchievementID.winsComplete10) == 90)
        #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: ten), MinesweeperAchievementID.winsComplete10) == 100)
    }

    @Test("wins.complete_50 boundary: 49/50 = 98%, 50/50 = 100%")
    func winsComplete50Boundary() {
        let low = MinesweeperWinFact(mode: .practice, difficulty: .beginner, elapsedSeconds: 60, flagsPlaced: 0, cumulativeWinCount: 49)
        let high = MinesweeperWinFact(mode: .practice, difficulty: .beginner, elapsedSeconds: 60, flagsPlaced: 0, cumulativeWinCount: 50)
        #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: low), MinesweeperAchievementID.winsComplete50) == 98)
        #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: high), MinesweeperAchievementID.winsComplete50) == 100)
    }

    @Test("wins.complete_200 boundary: 199/200 = 99.5%, 200/200 = 100%")
    func winsComplete200Boundary() {
        let low = MinesweeperWinFact(mode: .practice, difficulty: .beginner, elapsedSeconds: 60, flagsPlaced: 0, cumulativeWinCount: 199)
        let high = MinesweeperWinFact(mode: .practice, difficulty: .beginner, elapsedSeconds: 60, flagsPlaced: 0, cumulativeWinCount: 200)
        #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: low), MinesweeperAchievementID.winsComplete200) == 99.5)
        #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: high), MinesweeperAchievementID.winsComplete200) == 100)
    }

    @Test("Volume achievements count both modes combined (percent never gated by mode)")
    func volumeAppliesToBothModes() {
        let practiceFact = MinesweeperWinFact(mode: .practice, difficulty: .beginner, elapsedSeconds: 60, flagsPlaced: 0, cumulativeWinCount: 10)
        let dailyFact = MinesweeperWinFact(mode: .daily, difficulty: .beginner, elapsedSeconds: 60, flagsPlaced: 0, cumulativeWinCount: 10)
        #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: practiceFact), MinesweeperAchievementID.winsComplete10) == 100)
        #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: dailyFact), MinesweeperAchievementID.winsComplete10) == 100)
    }

    // MARK: - Difficulty

    @Test("Expert Cleared fires on any Expert win, either mode; never on non-Expert")
    func expertClearedGatesOnDifficultyOnly() {
        for mode in GameMode.allCases {
            let expert = MinesweeperWinFact(mode: mode, difficulty: .expert, elapsedSeconds: 300, flagsPlaced: 0, cumulativeWinCount: 1)
            #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: expert), MinesweeperAchievementID.expertFirstWin) == 100)
        }
        let intermediate = MinesweeperWinFact(mode: .practice, difficulty: .intermediate, elapsedSeconds: 300, flagsPlaced: 0, cumulativeWinCount: 1)
        #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: intermediate), MinesweeperAchievementID.expertFirstWin) == nil)
    }

    @Test("Full Spectrum requires all 3 difficulties AND daily mode; missing one difficulty does not qualify")
    func fullSpectrumRequiresAllThreeDifficulties() {
        let missingExpert = MinesweeperWinFact(
            mode: .daily, difficulty: .intermediate, elapsedSeconds: 60, flagsPlaced: 0, cumulativeWinCount: 3,
            dailyWinDifficulties: [.beginner, .intermediate]
        )
        #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: missingExpert), MinesweeperAchievementID.dailyFullSpectrum) == nil)

        let allThree = MinesweeperWinFact(
            mode: .daily, difficulty: .expert, elapsedSeconds: 60, flagsPlaced: 0, cumulativeWinCount: 3,
            dailyWinDifficulties: [.beginner, .intermediate, .expert]
        )
        #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: allThree), MinesweeperAchievementID.dailyFullSpectrum) == 100)
    }

    @Test("Full Spectrum never fires for a practice win even with all 3 difficulties recorded")
    func fullSpectrumGatedToDailyMode() {
        let fact = MinesweeperWinFact(
            mode: .practice, difficulty: .expert, elapsedSeconds: 60, flagsPlaced: 0, cumulativeWinCount: 3,
            dailyWinDifficulties: [.beginner, .intermediate, .expert]
        )
        #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: fact), MinesweeperAchievementID.dailyFullSpectrum) == nil)
    }

    // MARK: - Skill

    @Test("No Flags Needed fires only when zero flags were placed")
    func noFlagsNeededGatesOnFlagCount() {
        let noFlags = MinesweeperWinFact(mode: .practice, difficulty: .beginner, elapsedSeconds: 60, flagsPlaced: 0, cumulativeWinCount: 1)
        let withFlag = MinesweeperWinFact(mode: .practice, difficulty: .beginner, elapsedSeconds: 60, flagsPlaced: 1, cumulativeWinCount: 1)
        #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: noFlags), MinesweeperAchievementID.skillNoFlags) == 100)
        #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: withFlag), MinesweeperAchievementID.skillNoFlags) == nil)
    }

    @Test("Lightning Sweep boundary: Expert win at 179s qualifies, at 181s does not")
    func lightningSweepBoundary() {
        let fast = MinesweeperWinFact(mode: .practice, difficulty: .expert, elapsedSeconds: 179, flagsPlaced: 0, cumulativeWinCount: 1)
        let slow = MinesweeperWinFact(mode: .practice, difficulty: .expert, elapsedSeconds: 181, flagsPlaced: 0, cumulativeWinCount: 1)
        #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: fast), MinesweeperAchievementID.skillLightningExpert) == 100)
        #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: slow), MinesweeperAchievementID.skillLightningExpert) == nil)
    }

    @Test("Lightning Sweep never fires on a non-Expert win, even under 3 minutes")
    func lightningSweepGatesOnDifficulty() {
        let fact = MinesweeperWinFact(mode: .practice, difficulty: .beginner, elapsedSeconds: 5, flagsPlaced: 0, cumulativeWinCount: 1)
        #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: fact), MinesweeperAchievementID.skillLightningExpert) == nil)
    }

    // MARK: - Streak

    @Test("Streak achievements gate on daily mode and the 7/30 thresholds")
    func streakThresholds() {
        let under7 = MinesweeperWinFact(
            mode: .daily, difficulty: .beginner, elapsedSeconds: 60,
            flagsPlaced: 0, cumulativeWinCount: 6, consecutiveDailyStreak: 6
        )
        let exactly7 = MinesweeperWinFact(
            mode: .daily, difficulty: .beginner, elapsedSeconds: 60,
            flagsPlaced: 0, cumulativeWinCount: 7, consecutiveDailyStreak: 7
        )
        let exactly30 = MinesweeperWinFact(
            mode: .daily, difficulty: .beginner, elapsedSeconds: 60,
            flagsPlaced: 0, cumulativeWinCount: 30, consecutiveDailyStreak: 30
        )

        #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: under7), MinesweeperAchievementID.dailyStreak7) == nil)
        #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: exactly7), MinesweeperAchievementID.dailyStreak7) == 100)
        #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: exactly7), MinesweeperAchievementID.dailyStreak30) == nil)
        #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: exactly30), MinesweeperAchievementID.dailyStreak7) == 100)
        #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: exactly30), MinesweeperAchievementID.dailyStreak30) == 100)
    }

    @Test("A broken streak (reset to 1) does not qualify for either streak achievement")
    func brokenStreakDoesNotQualify() {
        let broken = MinesweeperWinFact(
            mode: .daily, difficulty: .beginner, elapsedSeconds: 60,
            flagsPlaced: 0, cumulativeWinCount: 40, consecutiveDailyStreak: 1
        )
        #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: broken), MinesweeperAchievementID.dailyStreak7) == nil)
        #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: broken), MinesweeperAchievementID.dailyStreak30) == nil)
    }

    @Test("Streak achievements never fire for a practice win regardless of streak count")
    func streakGatedToDailyMode() {
        let fact = MinesweeperWinFact(
            mode: .practice, difficulty: .beginner, elapsedSeconds: 60,
            flagsPlaced: 0, cumulativeWinCount: 40, consecutiveDailyStreak: 30
        )
        #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: fact), MinesweeperAchievementID.dailyStreak7) == nil)
        #expect(percent(MinesweeperAchievementEvaluator.evaluate(for: fact), MinesweeperAchievementID.dailyStreak30) == nil)
    }

    // MARK: - Shape

    @Test("allShortIds has exactly the 11 owner-approved achievements")
    func allShortIdsCount() {
        #expect(MinesweeperAchievementID.allShortIds.count == 11)
        #expect(Set(MinesweeperAchievementID.allShortIds).count == 11, "no duplicate short ids")
    }

    @Test("fullId prepends the MS achievement prefix")
    func fullIdPrefixing() {
        #expect(MinesweeperAchievementID.fullId("first_sweep") == "com.wei18.minesweeper.achievement.first_sweep")
    }
}
