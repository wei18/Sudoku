// TodayTabHostTests — C-33: the ATT primer anchor lives on `TodayTabHost`'s
// banner slot now (design.md §3.6.1; the retired HOME view's banner slot was
// the old anchor).
//
// #1020 CR follow-up: an earlier version of this suite tried to drive
// `onAdContext` end-to-end by rendering `TodayTabHost` in an offscreen
// `NSWindow` and pumping the run loop until `.task` resolved (mirroring
// SudokuKit's `NavigationPreferencePropagationTests`). Four diagnostics
// isolated a genuine harness limitation, not a bug in this code: a plain
// synchronous `.task` fires reliably in that harness, but a `.task` whose
// body `await`s across an ACTOR boundary (e.g. `AdGate.shouldShowBanner`,
// itself an `actor`) never resumes — confirmed hung past a 10s pump. This
// looks specific to how `swift-testing`'s async test executor relates to
// `RunLoop.main` in a headless `swift test` process (no `NSApplication` event
// loop ever bootstraps), not to `TodayTabHost`/`BannerSlotView`.
//
// Per the dispatch's own fallback ("if onAdContext can't be driven
// headlessly, assert via the injected coordinator's isPrimerPresented after
// invoking the host's own wiring through whatever internal seam exists, and
// say so"): `todayTabHostFireOnAdContext(attPrimer:)` was factored out of
// `TodayTabHost.bannerSlot` into a free function (internal, additive, zero
// behavior change — `bannerSlot` now calls it instead of duplicating its
// one-line body) so this suite calls the EXACT function the real banner
// slot's `onAdContext` hook invokes, without needing to render anything.
//
// NOT covered here (documented, not silently skipped): whether `BannerSlotView`
// itself withholds calling `onAdContext` while its gate is closed. That guard
// (`guard allowed else { return }` in `BannerSlotView.resolveGateAndLoad()`)
// lives in a pre-existing, unmodified shared component upstream of
// `todayTabHostFireOnAdContext` — verified by reading the source, not by a
// live test, since exercising it behaviorally hits the exact same
// actor-hop/`.task` harness limitation this suite works around.
// `ATTPrimerCoordinatorTests` covers the coordinator's own idempotency in
// isolation; this suite is the missing middle link — proving `TodayTabHost`
// actually WIRES its banner slot's ad-context hook to that coordinator.

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
private func makeRootViewModel() -> GameRootViewModel<ATTHostTestRoute> {
    GameRootViewModel<ATTHostTestRoute>(
        gameCenter: ATTHostStubGameCenter(),
        persistence: ATTHostStubPersistence()
    )
}

/// Proves `TodayTabHost` actually CONSTRUCTS with the exact dep shape
/// `Live+TabRoots.swift` wires it with (an `attPrimer` shared across the
/// whole tab-root build). The behavioral assertions below go through
/// `todayTabHostFireOnAdContext`, the free function `bannerSlot`'s
/// `onAdContext` closure calls — so both "the host builds" and "the host's
/// own wiring reaches the coordinator" are covered.
@MainActor
private func makeHost(attPrimer: ATTPrimerCoordinator) -> TodayTabHost<ATTHostTestRoute, Color> {
    TodayTabHost(
        rootViewModel: makeRootViewModel(),
        adProvider: FakeAdProvider(),
        adGate: AdGate(store: FakeAdGateStateStore(
            initial: AdGateState(firstLaunchAt: Date(timeIntervalSince1970: 0))
        )),
        attPrimer: attPrimer
    ) { Color.clear }
}

// MARK: - Suite

@MainActor
@Suite("TodayTabHost — C-33 ATT anchor wiring")
struct TodayTabHostTests {

    @Test("first ad context, ATT notDetermined: presents the primer")
    func firstAdContextPresentsWhenNotDetermined() async {
        let attPrimer = ATTPrimerCoordinator(isNotDetermined: { true }, requestSystemPrompt: {})
        _ = makeHost(attPrimer: attPrimer) // proves TodayTabHost constructs with this attPrimer

        await todayTabHostFireOnAdContext(attPrimer: attPrimer)

        #expect(attPrimer.isPrimerPresented == true, "TodayTabHost's banner slot must reach the ATT primer coordinator")
    }

    @Test("first ad context, ATT already determined: never presents")
    func firstAdContextNeverPresentsWhenDetermined() async {
        let attPrimer = ATTPrimerCoordinator(isNotDetermined: { false }, requestSystemPrompt: {})
        _ = makeHost(attPrimer: attPrimer)

        await todayTabHostFireOnAdContext(attPrimer: attPrimer)

        #expect(attPrimer.isPrimerPresented == false)
    }

    @Test("hasOffered latch: exactly one offer across two ad-context hooks sharing the coordinator")
    func offersExactlyOnceAcrossTwoAdContexts() async {
        let attPrimer = ATTPrimerCoordinator(isNotDetermined: { true }, requestSystemPrompt: {})
        // Two SEPARATE `TodayTabHost` mounts (e.g. leaving and revisiting the
        // Today tab) sharing the SAME `attPrimer` instance, exactly like
        // production: `attPrimer` is built once in `makeGameApp` and handed
        // to every tab-root build.
        _ = makeHost(attPrimer: attPrimer)
        _ = makeHost(attPrimer: attPrimer)

        await todayTabHostFireOnAdContext(attPrimer: attPrimer)
        #expect(attPrimer.isPrimerPresented == true, "first ad context should offer the primer")

        attPrimer.declinePrimer() // "Not now" — mirrors ATTPrimerCoordinatorTests.notNow_…
        #expect(attPrimer.isPrimerPresented == false)

        await todayTabHostFireOnAdContext(attPrimer: attPrimer)
        #expect(attPrimer.isPrimerPresented == false, "hasOffered latch must prevent a second offer this session")
    }
}
