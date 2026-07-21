// GameRootViewModelLeaveTests — Epic 1 (SDD-003): modal game presentation
// behavior of GameRootViewModel.
//
// Tests cover:
//   - presentGame(route:) sets activeGameRoute + isGamePresented
//   - dismissGame() clears both
//
// Note: Epic 2 (leave-confirmation dialog) was removed when the unified
// PauseOverlayView took over the leave flow. The former requestLeave /
// cancelLeave / confirmLeave / isShowingLeaveConfirmation tests are gone.

import Foundation
import Testing
import GameCenterClient
import SudokuGameState
import Persistence
import SudokuEngine
import Telemetry
@testable import GameAppKit

// MARK: - Test route enum

private enum LeaveRoute: Hashable, Sendable {
    case board(puzzleId: String)
    case home
}

// MARK: - Fakes (minimal)

private actor MinimalPersistence: PersistenceProtocol {
    func bootstrap() async throws {}
    func latestInProgress() async throws -> SavedGameSummary? { nil }
    func loadOrCreate(puzzleId: String, mode: Mode, difficulty: Difficulty) async throws -> GameSessionSnapshot {
        throw PersistenceError.zoneNotProvisioned
    }
    func save(_ snapshot: GameSessionSnapshot, puzzleId: String, mode: Mode, difficulty: Difficulty) async throws {}
    func markCompleted(_ summary: SavedGameSummary) async throws {}
    func deleteAbandoned(recordName: String) async throws {}
    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> { [] }
    func fetchCompletedDailyIdsByDay() async throws -> [String: Set<String>] { [:] }
    func fetchPersonalRecord(mode: Mode, difficulty: Difficulty) async throws -> PersonalRecord {
        PersonalRecord(
            recordName: "", mode: .daily, difficulty: .easy, bestTimeSeconds: nil,
            totalTimeSeconds: 0, completedCount: 0,
            lastUpdatedAt: Date(timeIntervalSince1970: 0), completedPuzzleIds: []
        )
    }
    func upsertPersonalRecord(_ record: PersonalRecord) async throws {}
}

private struct MinimalGameCenter: GameCenterClient {
    func authenticate() async throws -> GameCenterAuthState { .unauthenticated }
    func authStateUpdates() async -> AsyncStream<GameCenterAuthState> { AsyncStream { $0.finish() } }
    func submitScore(puzzleId: String, elapsedSeconds: Int, difficulty: Difficulty, leaderboardKind: LeaderboardKind) async throws {}
    func submitScore(leaderboardId: String, elapsedSeconds: Int) async throws {}
    func reportAchievement(_ achievement: AchievementProgress) async throws {}
    func fetchLeaderboardSlice(leaderboardId: String, scope: LeaderboardScope, aroundLocalPlayer: Bool, limit: Int) async throws -> LeaderboardSlice {
        LeaderboardSlice(leaderboardId: leaderboardId, scope: scope, entries: [], totalPlayerCount: 0, fetchedAt: Date(timeIntervalSince1970: 0))
    }
    func friendsAuthorizationStatus() async -> FriendsAuthStatus { .notDetermined }
    func requestFriendsAuthorization() async throws -> FriendsAuthStatus { .notDetermined }
}

// MARK: - Tests

@MainActor
@Suite("GameRootViewModel — modal presentation (Epic 1)")
struct GameRootViewModelLeaveTests {

    private func makeVM() -> GameRootViewModel<LeaveRoute> {
        GameRootViewModel<LeaveRoute>(
            gameCenter: MinimalGameCenter(),
            persistence: MinimalPersistence()
        )
    }

    // MARK: - Epic 1: Modal presentation

    @Test func presentGameSetsActiveRouteAndPresented() {
        let sut = makeVM()
        #expect(sut.activeGameRoute == nil)
        #expect(sut.isGamePresented == false)

        sut.presentGame(route: .board(puzzleId: "2026-06-12-easy"))

        #expect(sut.activeGameRoute == .board(puzzleId: "2026-06-12-easy"))
        #expect(sut.isGamePresented == true)
    }

    @Test func dismissGameClearsRouteAndPresented() {
        let sut = makeVM()
        sut.presentGame(route: .board(puzzleId: "2026-06-12-easy"))

        sut.dismissGame()

        #expect(sut.activeGameRoute == nil)
        #expect(sut.isGamePresented == false)
    }

    @Test func dismissGameWhenNotPresentedIsNoop() {
        let sut = makeVM()
        // Must not crash or set unexpected state. ("Noop" refers to the
        // presentation state below; since #761 a defensive call still bumps
        // `sessionTeardownCount` + kicks a resume refresh — both idempotent.)
        sut.dismissGame()

        #expect(sut.activeGameRoute == nil)
        #expect(sut.isGamePresented == false)
    }

    // MARK: - #761: session-teardown counter

    /// `dismissGame()` (the iOS fullScreenCover teardown hook) bumps
    /// `sessionTeardownCount` so environment-observing views (the Daily
    /// hubs) can react to a game session ending. Replaces the earlier
    /// `.onAppear`-based wiring, which sim-verification (#761) showed does
    /// not re-fire when a `fullScreenCover` dismisses.
    @Test func dismissGameIncrementsSessionTeardownCount() {
        let sut = makeVM()
        #expect(sut.sessionTeardownCount == 0)

        sut.presentGame(route: .board(puzzleId: "2026-06-12-easy"))
        sut.dismissGame()

        #expect(sut.sessionTeardownCount == 1)
    }

    /// `gameSessionDidTearDown()` is the macOS-path counterpart — called from
    /// `GameRoot`'s `path`-shrink branch (a board's Leave / completion Close
    /// pops `path` directly instead of going through `dismissGame()`). Must
    /// bump the same counter so both platforms drive the same signal.
    @Test func gameSessionDidTearDownIncrementsSessionTeardownCount() {
        let sut = makeVM()
        #expect(sut.sessionTeardownCount == 0)

        sut.gameSessionDidTearDown()

        #expect(sut.sessionTeardownCount == 1)
    }

    /// Repeated teardowns accumulate (not a latch) — each session end must
    /// produce a distinct `.onChange` firing for observers.
    @Test func sessionTeardownCountAccumulatesAcrossMultipleTeardowns() {
        let sut = makeVM()

        sut.presentGame(route: .board(puzzleId: "2026-06-12-easy"))
        sut.dismissGame()
        sut.gameSessionDidTearDown()
        sut.presentGame(route: .board(puzzleId: "2026-06-13-easy"))
        sut.dismissGame()

        #expect(sut.sessionTeardownCount == 3)
    }

    // MARK: - #912: path-shrink open-vs-close gating

    /// `GameRoot`'s `path`-shrink branch used to call `refreshResumeCandidate()`
    /// + `gameSessionDidTearDown()` unconditionally on ANY shrink — including
    /// `GameBoardRedirect`'s synthetic self-pop at board OPEN (see that
    /// type's doc). `GameBoardRedirect` now calls `presentGame(route:)`
    /// BEFORE popping, so `isGamePresented` is already `true` by the time
    /// `handlePathShrink()` runs for that pop — this is the exact case that
    /// must be filtered out.
    @Test func handlePathShrinkSkipsRefreshAndTeardownWhileGamePresented() {
        let sut = makeVM()
        sut.presentGame(route: .board(puzzleId: "2026-06-12-easy"))
        #expect(sut.isGamePresented == true)

        sut.handlePathShrink()

        #expect(sut.sessionTeardownCount == 0)
    }

    /// A genuine close (macOS `path` pop with no active game modal — the
    /// only way `path` ever shrinks on macOS, since `onPresentBoard` is
    /// iOS-only wired) must still bump the counter exactly as before —
    /// `handlePathShrink` narrows the false-positive, it must not turn into
    /// a "never refreshes" regression.
    @Test func handlePathShrinkBumpsTeardownWhenGameNotPresented() {
        let sut = makeVM()
        #expect(sut.isGamePresented == false)

        sut.handlePathShrink()

        #expect(sut.sessionTeardownCount == 1)
    }

    /// End-to-end sequence mirroring the real bug: a board opens (redirect
    /// pop while presented — must NOT bump), then later the session
    /// genuinely ends via `dismissGame()` (must bump). Proves open and close
    /// are now told apart, not just each in isolation.
    @Test func boardOpenPathShrinkIsSilentButLaterDismissStillCounts() {
        let sut = makeVM()

        sut.presentGame(route: .board(puzzleId: "2026-06-12-easy"))
        sut.handlePathShrink() // simulates GameBoardRedirect's open-time pop
        #expect(sut.sessionTeardownCount == 0)

        sut.dismissGame() // genuine close
        #expect(sut.sessionTeardownCount == 1)
    }
}
