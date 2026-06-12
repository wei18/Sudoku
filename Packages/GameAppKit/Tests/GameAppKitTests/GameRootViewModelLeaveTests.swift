// GameRootViewModelLeaveTests — Epic 1 + 2 (SDD-003): modal game presentation
// + leave confirmation behavior of GameRootViewModel.
//
// Tests cover:
//   - presentGame(route:) sets activeGameRoute + isGamePresented
//   - dismissGame() clears both
//   - requestLeave() sets isShowingLeaveConfirmation (never auto-dismisses)
//   - cancelLeave() clears isShowingLeaveConfirmation (no dismiss)
//   - confirmLeave() clears confirmation + dismisses game
//   - presentGame followed by confirmLeave results in no activeGameRoute

import Foundation
import Testing
import GameCenterClient
import GameState
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
@Suite("GameRootViewModel — modal presentation + leave confirmation (Epic 1+2)")
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
        // Must not crash or set unexpected state.
        sut.dismissGame()

        #expect(sut.activeGameRoute == nil)
        #expect(sut.isGamePresented == false)
    }

    // MARK: - Epic 2: Leave confirmation

    @Test func requestLeaveShowsConfirmation() {
        let sut = makeVM()
        #expect(sut.isShowingLeaveConfirmation == false)

        sut.requestLeave()

        #expect(sut.isShowingLeaveConfirmation == true)
    }

    @Test func cancelLeaveHidesConfirmationWithoutDismissing() {
        let sut = makeVM()
        sut.presentGame(route: .board(puzzleId: "2026-06-12-easy"))
        sut.requestLeave()

        sut.cancelLeave()

        #expect(sut.isShowingLeaveConfirmation == false)
        // Game remains presented.
        #expect(sut.isGamePresented == true)
        #expect(sut.activeGameRoute == .board(puzzleId: "2026-06-12-easy"))
    }

    // AC 2.3 note: this verifies only the dismiss leg. The save leg is
    // fulfilled cross-package by the board views' .onDisappear hooks
    // (MinesweeperBoardView.persistCurrentState #455, Sudoku BoardView.flush
    // #413) — not by the VM. See the load-bearing comment in GameRoot.swift.
    @Test func confirmLeaveHidesConfirmationAndDismissesGame() {
        let sut = makeVM()
        sut.presentGame(route: .board(puzzleId: "2026-06-12-easy"))
        sut.requestLeave()

        sut.confirmLeave()

        #expect(sut.isShowingLeaveConfirmation == false)
        #expect(sut.isGamePresented == false)
        #expect(sut.activeGameRoute == nil)
    }

    @Test func requestLeaveWhenNoGamePresentedIsHarmless() {
        let sut = makeVM()
        // requestLeave without a presented game (UI guard should prevent this,
        // but the VM must not crash).
        sut.requestLeave()

        #expect(sut.isShowingLeaveConfirmation == true)
        // confirmLeave still clears it safely.
        sut.confirmLeave()
        #expect(sut.isShowingLeaveConfirmation == false)
        #expect(sut.isGamePresented == false)
    }
}
