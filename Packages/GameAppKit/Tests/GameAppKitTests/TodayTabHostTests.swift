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

/// `eventually` for conditions that read actor state (the fake provider's counters).
@MainActor
private func eventuallyAsync(timeout: Duration = .seconds(2), _ condition: () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !(await condition()) {
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

    // #1078 2g: the two negative rows below no longer sleep a fixed 200ms.
    // Readiness is held on the fake's `markReady()` seam and released by the
    // test; a registered slot's load runs only AFTER the readiness path
    // (ready → ad context → sessionReady → loads), so a `refreshBanner()` call
    // arriving is the positive proof that the primer hook already ran.

    @Test("first ad context, ATT already determined: never presents")
    func firstAdContextNeverPresentsWhenDetermined() async {
        let attPrimer = ATTPrimerCoordinator(isNotDetermined: { false }, requestSystemPrompt: {})
        let provider = FakeAdProvider(readinessHeld: true)
        let session = makeBannerSession(adProvider: provider, adGate: openGate(), attPrimer: attPrimer)
        session.register(BannerSlotID())

        await session.start()
        provider.markReady()

        #expect(
            await eventuallyAsync { await provider.refreshCallCount >= 1 },
            "the slot load must arrive, proving the readiness path (and the primer hook) ran"
        )
        #expect(attPrimer.isPrimerPresented == false)
    }

    @Test("hasOffered latch: a declined primer is not re-offered on a later foreground")
    func declinedPrimerIsNotReoffered() async {
        let attPrimer = ATTPrimerCoordinator(isNotDetermined: { true }, requestSystemPrompt: {})
        // Every load fails, so the foreground repoll retries the slot and its
        // second `refreshBanner()` call proves the repoll ran to its load step.
        let provider = FakeAdProvider(
            scripted: ScriptedAdProviderState(refreshThrows: AdProviderError.unsupported),
            readinessHeld: true
        )
        let session = makeBannerSession(adProvider: provider, adGate: openGate(), attPrimer: attPrimer)
        session.register(BannerSlotID())

        await session.start()
        provider.markReady()
        #expect(await eventually { attPrimer.isPrimerPresented }, "first ad context should offer the primer")
        #expect(await eventuallyAsync { await provider.refreshCallCount >= 1 }, "the first load must have run")

        attPrimer.declinePrimer()
        await session.sceneDidBecomeActive()

        #expect(
            await eventuallyAsync { await provider.refreshCallCount >= 2 },
            "the repoll must retry the failed slot, proving it ran past the readiness step"
        )
        #expect(attPrimer.isPrimerPresented == false, "a declined primer must not be offered again this session")
    }
}
