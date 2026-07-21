import Foundation
import Testing
@testable import GameCenterClient
import Persistence
import SudokuGameState
import SudokuEngine

@Suite("GameCenterClient — achievement evaluator")
struct AchievementEvaluatorTests {

    private func utcDate(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        // swiftlint:disable:next force_unwrapping
        return formatter.date(from: string)!
    }

    private func progress(_ list: [AchievementProgress], _ id: String) -> AchievementProgress? {
        list.first { $0.achievementId == id }
    }

    @Test func firstPuzzleUnlocks() async throws {
        let persistence = StubPersistence()
        let evaluator = AchievementEvaluator(persistence: persistence)
        let today = utcDate("2026-05-19T12:00:00Z")
        let result = try await evaluator.evaluateForCompletion(
            puzzleId: "practice-AB-easy", mode: .practice, difficulty: .easy, mistakeCount: 0, today: today
        )
        let first = progress(result, "first_puzzle")
        #expect(first?.percentComplete == 100)
    }

    @Test func dailyStreak3DerivedFromPersistence() async throws {
        let persistence = StubPersistence()
        // Mark 3 consecutive UTC days ending today with at least one daily.
        await persistence.setDailyIds(forDay: "2026-05-19", ids: ["2026-05-19-easy"])
        await persistence.setDailyIds(forDay: "2026-05-18", ids: ["2026-05-18-medium"])
        await persistence.setDailyIds(forDay: "2026-05-17", ids: ["2026-05-17-hard"])
        let evaluator = AchievementEvaluator(persistence: persistence)
        let today = utcDate("2026-05-19T12:00:00Z")
        let result = try await evaluator.evaluateForCompletion(
            puzzleId: "2026-05-19-easy", mode: .daily, difficulty: .easy, mistakeCount: 0, today: today
        )
        #expect(progress(result, "daily.streak_3")?.percentComplete == 100)
        #expect(progress(result, "daily.streak_7") == nil)
    }

    @Test func practiceCompletePercentProgress() async throws {
        let persistence = StubPersistence()
        await persistence.setPracticeCompletedCount(easy: 30, medium: 30, hard: 10) // total 70
        let evaluator = AchievementEvaluator(persistence: persistence)
        let today = utcDate("2026-05-19T12:00:00Z")
        let result = try await evaluator.evaluateForCompletion(
            puzzleId: "practice-AB-easy", mode: .practice, difficulty: .easy, mistakeCount: 0, today: today
        )
        // 70 / 10 capped at 100; 70 / 100 == 70.
        #expect(progress(result, "practice.complete_10")?.percentComplete == 100)
        #expect(progress(result, "practice.complete_100")?.percentComplete == 70)
    }

    @Test func dailySweepRequiresAllThreeDifficulties() async throws {
        let persistence = StubPersistence()
        await persistence.setDailyIds(
            forDay: "2026-05-19",
            ids: ["2026-05-19-easy", "2026-05-19-medium", "2026-05-19-hard"]
        )
        let evaluator = AchievementEvaluator(persistence: persistence)
        let today = utcDate("2026-05-19T12:00:00Z")
        let result = try await evaluator.evaluateForCompletion(
            puzzleId: "2026-05-19-hard", mode: .daily, difficulty: .hard, mistakeCount: 0, today: today
        )
        #expect(progress(result, "daily.sweep")?.percentComplete == 100)

        // Missing one difficulty → not awarded.
        await persistence.setDailyIds(forDay: "2026-05-19", ids: ["2026-05-19-easy", "2026-05-19-medium"])
        let partial = try await evaluator.evaluateForCompletion(
            puzzleId: "2026-05-19-medium", mode: .daily, difficulty: .medium, mistakeCount: 1, today: today
        )
        #expect(progress(partial, "daily.sweep") == nil)
    }

    @Test func hardMasterCountsAcrossModes() async throws {
        let persistence = StubPersistence()
        await persistence.setHardCount(daily: 5, practice: 5) // 10 / 25 == 40%
        let evaluator = AchievementEvaluator(persistence: persistence)
        let today = utcDate("2026-05-19T12:00:00Z")
        let result = try await evaluator.evaluateForCompletion(
            puzzleId: "2026-05-19-hard", mode: .daily, difficulty: .hard, mistakeCount: 5, today: today
        )
        #expect(progress(result, "hard.master")?.percentComplete == 40)
    }

    @Test func idempotentDoubleEvaluation() async throws {
        // The evaluator is pure over Persistence state: invoking it twice
        // with the same inputs returns the same outputs. Mirrors GameKit's
        // own "max-of-reported-percent" idempotency model.
        let persistence = StubPersistence()
        let evaluator = AchievementEvaluator(persistence: persistence)
        let today = utcDate("2026-05-19T12:00:00Z")
        let first = try await evaluator.evaluateForCompletion(
            puzzleId: "practice-AB-easy", mode: .practice, difficulty: .easy, mistakeCount: 0, today: today
        )
        let second = try await evaluator.evaluateForCompletion(
            puzzleId: "practice-AB-easy", mode: .practice, difficulty: .easy, mistakeCount: 0, today: today
        )
        #expect(first == second)
    }

    // MARK: - v2.6 batch: 5 new achievements

    @Test func perfectRunUnlocksWhenZeroMistakes() async throws {
        let persistence = StubPersistence()
        let evaluator = AchievementEvaluator(persistence: persistence)
        let today = utcDate("2026-05-19T12:00:00Z")

        // Zero mistakes → awarded.
        let perfect = try await evaluator.evaluateForCompletion(
            puzzleId: "practice-AB-easy", mode: .practice, difficulty: .easy, mistakeCount: 0, today: today
        )
        #expect(progress(perfect, "perfect_run")?.percentComplete == 100)

        // One or more mistakes → not awarded.
        let imperfect = try await evaluator.evaluateForCompletion(
            puzzleId: "practice-AB-easy", mode: .practice, difficulty: .easy, mistakeCount: 1, today: today
        )
        #expect(progress(imperfect, "perfect_run") == nil, "perfect_run must not fire when mistakeCount > 0")
    }

    @Test func perfectRunIdempotency() async throws {
        // Calling evaluator twice with mistakeCount=0 returns identical results.
        let persistence = StubPersistence()
        let evaluator = AchievementEvaluator(persistence: persistence)
        let today = utcDate("2026-05-19T12:00:00Z")
        let first = try await evaluator.evaluateForCompletion(
            puzzleId: "practice-AB-easy", mode: .practice, difficulty: .easy, mistakeCount: 0, today: today
        )
        let second = try await evaluator.evaluateForCompletion(
            puzzleId: "practice-AB-easy", mode: .practice, difficulty: .easy, mistakeCount: 0, today: today
        )
        #expect(first == second)
    }

    @Test func dailyStreak30DoesNotFireOnTwentyNineDays() async throws {
        let persistence = StubPersistence()
        var calendar = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let anchor = utcDate("2026-05-19T12:00:00Z")
        // 29 consecutive days only — the 30-day boundary must NOT fire.
        for dayOffset in 0..<29 {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: anchor) else { continue }
            let key = UTCDay.string(from: day)
            await persistence.setDailyIds(forDay: key, ids: ["\(key)-easy"])
        }
        let evaluator = AchievementEvaluator(persistence: persistence)
        let result = try await evaluator.evaluateForCompletion(
            puzzleId: "2026-05-19-easy", mode: .daily, difficulty: .easy, mistakeCount: 0, today: anchor
        )
        #expect(progress(result, "daily.streak_30") == nil, "streak_30 must not fire on a 29-day streak")
        // The 7-day tier still fires.
        #expect(progress(result, "daily.streak_7")?.percentComplete == 100)
    }

    @Test func dailyStreak30UnlocksOnThirtyConsecutiveDays() async throws {
        let persistence = StubPersistence()
        // Mark 30 consecutive UTC days (May 19 back to April 20).
        var calendar = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let anchor = utcDate("2026-05-19T12:00:00Z")
        for dayOffset in 0..<30 {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: anchor) else { continue }
            let key = UTCDay.string(from: day)
            await persistence.setDailyIds(forDay: key, ids: ["\(key)-easy"])
        }
        let evaluator = AchievementEvaluator(persistence: persistence)
        let result = try await evaluator.evaluateForCompletion(
            puzzleId: "2026-05-19-easy", mode: .daily, difficulty: .easy, mistakeCount: 0, today: anchor
        )
        #expect(progress(result, "daily.streak_30")?.percentComplete == 100)
        // streak_7 (v1) must also fire when streak ≥ 30.
        #expect(progress(result, "daily.streak_7")?.percentComplete == 100)
    }

    @Test func expertSolverUnlocksOnHardDifficulty() async throws {
        let persistence = StubPersistence()
        let evaluator = AchievementEvaluator(persistence: persistence)
        let today = utcDate("2026-05-19T12:00:00Z")

        // Hard completion → awarded.
        let hardResult = try await evaluator.evaluateForCompletion(
            puzzleId: "2026-05-19-hard", mode: .daily, difficulty: .hard, mistakeCount: 0, today: today
        )
        #expect(progress(hardResult, "expert_solver")?.percentComplete == 100)

        // Easy completion → not awarded.
        let easyResult = try await evaluator.evaluateForCompletion(
            puzzleId: "2026-05-19-easy", mode: .daily, difficulty: .easy, mistakeCount: 0, today: today
        )
        #expect(progress(easyResult, "expert_solver") == nil, "expert_solver must not fire on Easy difficulty")

        // Medium completion → not awarded.
        let medResult = try await evaluator.evaluateForCompletion(
            puzzleId: "practice-AB-medium", mode: .practice, difficulty: .medium, mistakeCount: 0, today: today
        )
        #expect(progress(medResult, "expert_solver") == nil, "expert_solver must not fire on Medium difficulty")
    }

    @Test func expertSolverIdempotency() async throws {
        // Idempotency: two hard completions yield identical achievement sets.
        let persistence = StubPersistence()
        let evaluator = AchievementEvaluator(persistence: persistence)
        let today = utcDate("2026-05-19T12:00:00Z")
        let first = try await evaluator.evaluateForCompletion(
            puzzleId: "2026-05-19-hard", mode: .daily, difficulty: .hard, mistakeCount: 0, today: today
        )
        let second = try await evaluator.evaluateForCompletion(
            puzzleId: "2026-05-19-hard", mode: .daily, difficulty: .hard, mistakeCount: 0, today: today
        )
        #expect(first == second)
    }
}

// MARK: - Test seam

private actor StubPersistence: PersistenceProtocol {
    /// `YYYY-MM-DD` → completed daily puzzleIds for that UTC day.
    private var dailyIds: [String: Set<String>] = [:]
    private var practiceCounts: [String: Int] = ["easy": 0, "medium": 0, "hard": 0]
    private var hardCounts: [String: Int] = ["daily": 0, "practice": 0]

    func setDailyIds(forDay key: String, ids: Set<String>) {
        dailyIds[key] = ids
    }

    func setPracticeCompletedCount(easy: Int, medium: Int, hard: Int) {
        practiceCounts = ["easy": easy, "medium": medium, "hard": hard]
    }

    func setHardCount(daily: Int, practice: Int) {
        hardCounts = ["daily": daily, "practice": practice]
    }

    // MARK: PersistenceProtocol — only the methods used by AchievementEvaluator

    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> {
        let key = UTCDay.string(from: date)
        return dailyIds[key] ?? []
    }

    func fetchCompletedDailyIdsByDay() async throws -> [String: Set<String>] { dailyIds }

    func fetchPersonalRecord(mode: Mode, difficulty: Difficulty) async throws -> PersonalRecord {
        var count = 0
        if mode == .practice {
            count = practiceCounts[difficulty.rawValue] ?? 0
        } else if mode == .daily, difficulty == .hard {
            count = hardCounts["daily"] ?? 0
        }
        if mode == .practice, difficulty == .hard {
            count = max(count, hardCounts["practice"] ?? 0)
        }
        return PersonalRecord(
            recordName: "\(mode.rawValue)-\(difficulty.rawValue)",
            mode: mode,
            difficulty: difficulty,
            bestTimeSeconds: nil,
            totalTimeSeconds: 0,
            completedCount: count,
            lastUpdatedAt: Date(timeIntervalSince1970: 0),
            completedPuzzleIds: []
        )
    }

    // Unused-by-this-suite methods — return defaults.
    func bootstrap() async throws {}
    func latestInProgress() async throws -> SavedGameSummary? { nil }
    func loadOrCreate(puzzleId: String, mode: Mode, difficulty: Difficulty) async throws -> GameSessionSnapshot {
        throw PersistenceError.zoneNotProvisioned
    }
    func save(
        _ snapshot: GameSessionSnapshot,
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws {}
    func markCompleted(_ summary: SavedGameSummary) async throws {}
    func deleteAbandoned(recordName: String) async throws {}
    func upsertPersonalRecord(_ record: PersonalRecord) async throws {}
}
