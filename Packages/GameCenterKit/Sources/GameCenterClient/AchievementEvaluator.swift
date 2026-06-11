// AchievementEvaluator — computes the 8 v1 achievements from Persistence
// counts (docs/v1/design.md §How.3.2 + §How.3.3 Sink pseudocode).
//
// Design rationale: achievements are re-derived from persisted state on
// each completion rather than incrementally tracked in memory. This
// guarantees correctness across:
// - offline completions that fire later, out of order
// - cross-device completions arriving via CloudKit sync
// - reinstalls that wipe local state but preserve Private DB records
//
// Trade-off: every `puzzleCompleted` event triggers ~10 Persistence reads
// (1 for sweep, 7 for streak_7 — using the same `fetchCompletedDailyIds`
// per day, with the request-day cached internally). Acceptable: a
// completion is at most once per minute and Persistence reads from the
// local SwiftData mirror anyway (§How.6.5 not a network round trip).
//
// Achievement ID prefix `com.wei18.sudoku.achievement.` is NOT applied
// here — the evaluator emits the short ids from `AchievementID` (#466:
// previously raw literals; the SSOT enum is now actually consumed).
// Prefix is added at submit time by `GameCenterSink` (§How.3.2 末段).

public import Foundation
public import Persistence
public import SudokuEngine

public actor AchievementEvaluator: Sendable {

    private let persistence: any PersistenceProtocol

    public init(persistence: any PersistenceProtocol) {
        self.persistence = persistence
    }

    /// Evaluate all 8 v1 achievements for the just-completed puzzle.
    /// `today` is the wall-clock instant of completion; the evaluator
    /// re-derives the calendar UTC day from it.
    public func evaluateForCompletion(
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty,
        today: Date
    ) async throws -> [AchievementProgress] {
        var results: [AchievementProgress] = []

        // 1. first_puzzle — always 100% on any completion.
        results.append(AchievementProgress(achievementId: AchievementID.firstPuzzle, percentComplete: 100))

        // 2. daily.complete_one — Daily mode only, 100% on first daily.
        if mode == .daily {
            results.append(AchievementProgress(achievementId: AchievementID.dailyCompleteOne, percentComplete: 100))
        }

        // 3 + 4. Streaks — count consecutive UTC days (incl. today) with
        // at least one daily completion.
        let streak = try await consecutiveDailyStreak(endingOn: today, maxDays: 7)
        if streak >= 3 {
            results.append(AchievementProgress(achievementId: AchievementID.dailyStreak3, percentComplete: 100))
        }
        if streak >= 7 {
            results.append(AchievementProgress(achievementId: AchievementID.dailyStreak7, percentComplete: 100))
        }

        // 5 + 6. Practice counts — sum across difficulties.
        let practiceCount = try await totalCompletedCount(mode: .practice)
        results.append(AchievementProgress(
            achievementId: AchievementID.practiceComplete10,
            percentComplete: percent(progress: practiceCount, target: 10)
        ))
        results.append(AchievementProgress(
            achievementId: AchievementID.practiceComplete100,
            percentComplete: percent(progress: practiceCount, target: 100)
        ))

        // 7. hard.master — hard completions across both modes.
        let hardCount = try await totalHardCount()
        results.append(AchievementProgress(
            achievementId: AchievementID.hardMaster,
            percentComplete: percent(progress: hardCount, target: 25)
        ))

        // 8. daily.sweep — all 3 difficulties of today's daily.
        // M5 (issue #65): build puzzleId suffixes from `Difficulty.rawValue`
        // so the trio remains in lockstep with the enum (compiler will catch
        // a future case addition).
        let todayKey = UTCDay.string(from: today)
        let todaysIds = try await persistence.fetchCompletedDailyIds(for: today)
        let sweepDone = Difficulty.allCases.allSatisfy { diff in
            todaysIds.contains("\(todayKey)-\(diff.rawValue)")
        }
        if sweepDone {
            results.append(AchievementProgress(achievementId: AchievementID.dailySweep, percentComplete: 100))
        }

        _ = (puzzleId, difficulty) // referenced through the puzzleId in higher-level logging
        return results
    }

    // MARK: - Persistence-backed helpers

    /// Number of consecutive UTC days ending on `endingOn` that have at
    /// least one daily completion. Caps at `maxDays` so we never request
    /// more days than the largest streak achievement (7 in v1).
    private func consecutiveDailyStreak(endingOn endDate: Date, maxDays: Int) async throws -> Int {
        var streak = 0
        for offset in 0..<maxDays {
            guard let day = Self.utcDay(offsetFrom: endDate, byDays: -offset) else { break }
            let ids = try await persistence.fetchCompletedDailyIds(for: day)
            if ids.isEmpty {
                break
            }
            streak += 1
        }
        return streak
    }

    private func totalCompletedCount(mode: Mode) async throws -> Int {
        var total = 0
        for difficulty in Difficulty.allCases {
            let record = try await persistence.fetchPersonalRecord(mode: mode, difficulty: difficulty)
            total += record.completedCount
        }
        return total
    }

    private func totalHardCount() async throws -> Int {
        var total = 0
        for mode in Mode.allCases {
            let record = try await persistence.fetchPersonalRecord(mode: mode, difficulty: .hard)
            total += record.completedCount
        }
        return total
    }

    // MARK: - Math + date helpers

    private func percent(progress: Int, target: Int) -> Double {
        guard target > 0 else { return 0 }
        let raw = Double(progress) / Double(target) * 100.0
        return min(100.0, max(0.0, raw))
    }

    static func utcDay(offsetFrom anchor: Date, byDays days: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(byAdding: .day, value: days, to: anchor)
    }
}
