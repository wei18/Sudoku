// TodayTabHostTests — C-33: the ATT primer is requested at the session's first
// ad-relevant moment. Since #1058 the request is made by the session-scoped
// `BannerSessionModel` (its readiness task runs `onAdContext`), and
// `makeGameApp` wires that hook to `ATTPrimerCoordinator` through
// `makeBannerSession(adProvider:adGate:attPrimer:)`. This suite drives that
// exact wiring function, and pins that `TodayTabHost` still constructs around
// the Today content with only its non-monetization inputs.

import Foundation
import SwiftUI
import Testing
import GameCenterClient
import MonetizationCore
import MonetizationTesting
import MonetizationUI
import Persistence
import SudokuEngine
import SudokuGameState
@testable import GameAppKit

// MARK: - Test route + fakes (mirrors GameRootViewModelTabPathTests' shape)

private enum ATTHostTestRoute: Hashable, Sendable {
    case settings
}

private actor ATTHostStubPersistence: PersistenceProtocol {
    func bootstrap() async throws {}
    func latestInProgress() async throws -> SavedGameSummary? { nil }
    func loadOrCreate(
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> GameSessionSnapshot {
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
    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> { [] }
    func fetchCompletedDailyIdsByDay() async throws -> [String: Set<String>] { [:] }
    func fetchPersonalRecord(mode: Mode, difficulty: Difficulty) async throws -> PersonalRecord {
        PersonalRecord(
            recordName: "",
            mode: .daily,
            difficulty: .easy,
            bestTimeSeconds: nil,
            totalTimeSeconds: 0,
            completedCount: 0,
            lastUpdatedAt: Date(timeIntervalSince1970: 0),
            completedPuzzleIds: []
        )
    }
    func upsertPersonalRecord(_ record: PersonalRecord) async throws {}
}

private struct ATTHostStubGameCenter: GameCenterClient {
    func authenticate() async throws -> GameCenterAuthState { .unauthenticated }
    func authStateUpdates() async -> AsyncStream<GameCenterAuthState> {
        AsyncStream { $0.finish() }
    }
    func submitScore(puzzleId: String, elapsedSeconds: Int, leaderboardKind: LeaderboardKind) async throws {}
    func submitScore(leaderboardId: String, elapsedSeconds: Int) async throws {}
    func reportAchievement(_ achievement: AchievementProgress) async throws {}
}

@MainActor
private func openGate() -> AdGate {
    AdGate(store: FakeAdGateStateStore(initial: AdGateState(firstLaunchAt: Date(timeIntervalSince1970: 0))))
}

/// Polls `condition` every 10ms until it holds or `timeout` elapses.
@MainActor
private func eventually(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        if ContinuousClock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

// MARK: - Suite

@MainActor
@Suite("TodayTabHost + banner session — C-33 ATT anchor wiring", .timeLimit(.minutes(1)))
struct TodayTabHostTests {

    @Test("TodayTabHost constructs around the Today content")
    func hostConstructs() {
        let rootViewModel = GameRootViewModel<ATTHostTestRoute>(
            gameCenter: ATTHostStubGameCenter(),
            persistence: ATTHostStubPersistence()
        )
        _ = TodayTabHost(rootViewModel: rootViewModel) { Color.clear }
    }

    @Test("first ad context, ATT notDetermined: presents the primer")
    func firstAdContextPresentsWhenNotDetermined() async {
        let attPrimer = ATTPrimerCoordinator(isNotDetermined: { true }, requestSystemPrompt: {})
        let session = makeBannerSession(adProvider: FakeAdProvider(), adGate: openGate(), attPrimer: attPrimer)

        await session.start()

        #expect(await eventually { attPrimer.isPrimerPresented }, "the session's ad-context hook must reach the ATT primer")
    }

    @Test("first ad context, ATT already determined: never presents")
    func firstAdContextNeverPresentsWhenDetermined() async throws {
        let attPrimer = ATTPrimerCoordinator(isNotDetermined: { false }, requestSystemPrompt: {})
        let session = makeBannerSession(adProvider: FakeAdProvider(), adGate: openGate(), attPrimer: attPrimer)

        await session.start()
        try await Task.sleep(for: .milliseconds(200))

        #expect(attPrimer.isPrimerPresented == false)
    }

    @Test("hasOffered latch: a declined primer is not re-offered on a later foreground")
    func declinedPrimerIsNotReoffered() async throws {
        let attPrimer = ATTPrimerCoordinator(isNotDetermined: { true }, requestSystemPrompt: {})
        let session = makeBannerSession(adProvider: FakeAdProvider(), adGate: openGate(), attPrimer: attPrimer)

        await session.start()
        #expect(await eventually { attPrimer.isPrimerPresented }, "first ad context should offer the primer")

        attPrimer.declinePrimer()
        await session.sceneDidBecomeActive()
        try await Task.sleep(for: .milliseconds(200))

        #expect(attPrimer.isPrimerPresented == false, "a declined primer must not be offered again this session")
    }
}
