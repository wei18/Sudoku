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
    /// M10 (issue #67): unified error funnel for the two previously-swallowed
    /// branches (submitScore / reportAchievement). No-retry policy from
    /// §How.3.4 stays — but the failure is now observable instead of silent.
    private let errorReporter: any ErrorReporter
    /// Achievement id prefix per docs/v1/design.md §How.3.2.
    private let achievementPrefix = "com.wei18.sudoku.achievement."

    public init(
        client: any GameCenterClient,
        guards: SubmitGuards,
        achievements: AchievementEvaluator,
        authStateProvider: @escaping @Sendable () async -> GameCenterAuthState,
        errorReporter: any ErrorReporter = NoopErrorReporter(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.client = client
        self.guards = guards
        self.achievements = achievements
        self.authStateProvider = authStateProvider
        self.errorReporter = errorReporter
        self.clock = clock
    }

    public func receive(_ event: TelemetryEvent) async {
        guard case let .puzzleCompleted(puzzleId, mode, difficulty, elapsedSeconds, mistakeCount) = event else {
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
        await reportAchievements(puzzleId: puzzleId, mode: mode, difficulty: difficulty, mistakeCount: mistakeCount)
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
            // M10 (issue #67): policy stays (no retry queue per §How.3.4)
            // but failure is now observable via the funnel so engineering
            // can see the score-submit error in OSLog instead of silence.
            await errorReporter.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "GameCenterSink.submitScore"
            )
        }
    }

    private func reportAchievements(puzzleId: String, mode: Mode, difficulty: Difficulty, mistakeCount: Int) async {
        do {
            let progresses = try await achievements.evaluateForCompletion(
                puzzleId: puzzleId,
                mode: mode,
                difficulty: difficulty,
                mistakeCount: mistakeCount,
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
                    // M10 (issue #67): policy stays (no retry per §How.3.4)
                    // but funnel records the failure for OSLog visibility.
                    await errorReporter.report(
                        UserFacingError.classify(error),
                        underlying: error,
                        source: "GameCenterSink.reportAchievement"
                    )
                }
            }
        } catch {
            // M10 (issue #67): evaluator failure (e.g. Persistence
            // unavailable) — achievement reporting is non-critical and
            // will re-derive on the next completion; funnel reports so
            // the underlying Persistence error is observable.
            await errorReporter.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "GameCenterSink.evaluateForCompletion"
            )
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
