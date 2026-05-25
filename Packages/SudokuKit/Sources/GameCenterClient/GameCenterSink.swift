// GameCenterSink — TelemetrySink that wires `puzzleCompleted` events to
// GameCenter score submission + achievement reporting.
//
// Per docs/v1/design.md §How.3.3 fan-out pseudocode:
// 1. If auth state is not `.authenticated`, no-op silently (no submit,
//    no achievements). Includes `.restricted` / `.unavailableInRegion` /
//    `.unauthenticated` — every degraded state.
// 2. If mode == "daily" AND SubmitGuards.shouldSubmit, submit the score
//    and mark the puzzleId. Score is gated by all three Daily-only rules
//    (Step 7.3): practice-prefix block, dedup, cross-day check.
// 3. Always evaluate + report achievements (Step 7.4) when authenticated.
//    Achievements are mode-agnostic (e.g. practice completions count
//    toward `practice.complete_10`). Achievement id prefixing
//    (`com.wei18.sudoku.achievement.`) is applied here.
//
// Error handling: TelemetrySink.receive(_:) is non-throwing. Any failure
// from GameCenterClient.submitScore / .reportAchievement is swallowed —
// these branches are best-effort. We do NOT retry, queue, or surface to
// the user: docs/v1/design.md §How.3.4 explicitly disallows an offline retry queue
// in v1 (CloudKit `PersonalRecord` + `SavedGame` are the durable record
// of truth; GC is the "炫耀面" leaderboard layer only). The errors are
// observable via the GameCenterClient's own OSLog in production.

public import Foundation
internal import SudokuEngine
public import Telemetry

public actor GameCenterSink: TelemetrySink {

    private let client: any GameCenterClient
    private let guards: SubmitGuards
    private let achievements: AchievementEvaluator
    private let authStateProvider: @Sendable () async -> GameCenterAuthState
    private let clock: @Sendable () -> Date
    /// Achievement id prefix per docs/v1/design.md §How.3.2.
    private let achievementPrefix = "com.wei18.sudoku.achievement."

    public init(
        client: any GameCenterClient,
        guards: SubmitGuards,
        achievements: AchievementEvaluator,
        authStateProvider: @escaping @Sendable () async -> GameCenterAuthState,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.guards = guards
        self.achievements = achievements
        self.authStateProvider = authStateProvider
        self.clock = clock
    }

    public func receive(_ event: TelemetryEvent) async {
        guard case let .puzzleCompleted(puzzleId, mode, difficulty, elapsedSeconds) = event else {
            return
        }
        let authState = await authStateProvider()
        guard case .authenticated = authState else {
            return
        }
        await submitScoreIfEligible(
            puzzleId: puzzleId,
            mode: mode,
            difficulty: difficulty,
            elapsedSeconds: elapsedSeconds
        )
        await reportAchievements(puzzleId: puzzleId, mode: mode, difficulty: difficulty)
    }

    private func submitScoreIfEligible(
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty,
        elapsedSeconds: Int
    ) async {
        guard mode == .daily else { return }
        // M5 (issue #65): exhaustive switch — no `nil` case, no silent
        // score-drop. A typo at the call site fails to compile rather
        // than reaching this branch with a junk string.
        let kind = Self.leaderboardKind(forDifficulty: difficulty)
        let allow = await guards.shouldSubmit(puzzleId: puzzleId)
        guard allow else { return }
        do {
            try await client.submitScore(
                puzzleId: puzzleId,
                elapsedSeconds: elapsedSeconds,
                difficulty: difficulty,
                leaderboardKind: kind
            )
            await guards.markSubmitted(puzzleId: puzzleId)
        } catch {
            // Swallowed by design (§How.3.4: no offline retry queue;
            // PersonalRecord on Private DB is the durable record).
        }
    }

    private func reportAchievements(puzzleId: String, mode: Mode, difficulty: Difficulty) async {
        do {
            let progresses = try await achievements.evaluateForCompletion(
                puzzleId: puzzleId,
                mode: mode,
                difficulty: difficulty,
                today: clock()
            )
            for progress in progresses {
                let prefixed = AchievementProgress(
                    achievementId: achievementPrefix + progress.achievementId,
                    percentComplete: progress.percentComplete
                )
                do {
                    try await client.reportAchievement(prefixed)
                } catch {
                    // Swallowed per §How.3.4.
                }
            }
        } catch {
            // Evaluator failures (e.g. Persistence unavailable) are
            // swallowed: achievement reporting is non-critical and will
            // re-derive correctly on the next completion.
        }
    }

    /// M5 (issue #65): non-optional, exhaustive on `Difficulty`. The
    /// compiler now refuses to let this map drift out of sync with new
    /// difficulty cases.
    private static func leaderboardKind(forDifficulty difficulty: Difficulty) -> LeaderboardKind {
        switch difficulty {
        case .easy: return .dailyEasy
        case .medium: return .dailyMedium
        case .hard: return .dailyHard
        }
    }
}
