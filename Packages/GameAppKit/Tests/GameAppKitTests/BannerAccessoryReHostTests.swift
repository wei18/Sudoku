// BannerAccessoryReHostTests — T2 for #1080: the accessory's banner lease
// must survive `tabViewBottomAccessory` natively re-hosting its content
// (push, pop, sheet dismissal — see `tabview-bottom-accessory-rehosts-content`).
//
// Separate file, not added into `BannerAccessoryPinTests`'s suite (PM's
// "T2 可以直接加進同一個 suite" was permissive, not mandatory): folding T2's
// helper in there pushed that file to 438 lines, over the repo's
// `file_length` ceiling (400, SwiftLint `--strict`). This file duplicates
// the minimal stubs it needs (sentinel route/factory, `GameRootViewModel`
// doubles, the `eventually` poll) rather than loosening any `private` in
// `BannerAccessoryPinTests.swift` to share them across files — the same
// call the #1080 remount probe's own (unshipped) teardown test made for the
// same reason ("Mirrors TodayTabHostTests'... those are file-`private`, so
// this throwaway file needs its own copies").
//
// iOS only — `BannerAccessoryView` (and `GameRoot`'s accessory wiring it
// exercises) only compiles `#if os(iOS)`.

#if os(iOS)

import Foundation
import SwiftUI
import Testing
import UIKit
import GameCenterClient
import MonetizationCore
import MonetizationUI
import MonetizationTesting
import Persistence
import GameShellUI
import SudokuEngine
import SudokuGameState
@testable import GameAppKit

private enum ReHostSentinelRoute: Hashable, Sendable {
    case first
    case settings
}

private struct ReHostSentinelFactory: RouteFactory {
    typealias Route = ReHostSentinelRoute

    @MainActor
    func view(for route: ReHostSentinelRoute, path: Binding<[ReHostSentinelRoute]>?) -> AnyView {
        AnyView(Text("destination"))
    }
}

private actor ReHostStubPersistence: PersistenceProtocol {
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

private struct ReHostStubGameCenter: GameCenterClient {
    func authenticate() async throws -> GameCenterAuthState { .unauthenticated }
    func authStateUpdates() async -> AsyncStream<GameCenterAuthState> {
        AsyncStream { $0.finish() }
    }
    func submitScore(puzzleId: String, elapsedSeconds: Int, leaderboardKind: LeaderboardKind) async throws {}
    func submitScore(leaderboardId: String, elapsedSeconds: Int) async throws {}
    func reportAchievement(_ achievement: AchievementProgress) async throws {}
}

/// Polls `condition` every 10ms until it holds or `timeout` elapses (mirrors
/// `BannerAccessoryPinTests.eventually`).
@MainActor
private func eventually(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        if ContinuousClock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

/// A `BannerSessionModel` with an open gate, backed by the given (or a
/// fresh) `FakeAdProvider` so the test can read `refreshCallCount` after
/// driving the hosted window. NOT started here — `GameRoot.onAppear` does
/// that, exactly like production.
@MainActor
private func makeOpenSession(provider: FakeAdProvider) -> BannerSessionModel {
    let state = AdGateState(firstLaunchAt: Date(timeIntervalSince1970: 0))
    let adGate = AdGate(store: FakeAdGateStateStore(initial: state))
    return BannerSessionModel(adProvider: provider, adGate: adGate)
}

/// Hosts the REAL `GameRoot`, same shape as `BannerAccessoryPinTests
/// .makeHostedGameRoot`, and also returns the view model — needed here to
/// push/pop a route on a tab's own `NavigationStack`.
@MainActor
private func makeHostedGameRoot(
    session: BannerSessionModel
) -> (window: UIWindow, viewModel: GameRootViewModel<ReHostSentinelRoute>) {
    let viewModel = GameRootViewModel<ReHostSentinelRoute>(
        gameCenter: ReHostStubGameCenter(),
        persistence: ReHostStubPersistence()
    )
    let root = GameRoot(
        viewModel: viewModel,
        bannerSession: session,
        routeFactory: ReHostSentinelFactory(),
        settingsRoute: .settings,
        toastController: nil,
        successTint: .green,
        failureTint: .red,
        infoTint: .blue,
        tabRoot: { tab in Text(tab.rawValue) },
        bottomAccessory: { makeBottomAccessory() }
    )
    .environment(\.bannerSession, session)

    let controller = UIHostingController(rootView: root)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    window.layoutIfNeeded()
    return (window, viewModel)
}

@MainActor
@Suite("Banner accessory re-host lease (#1080)")
struct BannerAccessoryReHostTests {

    /// Mutation target (#1080, executed and reverted — see the dispatch
    /// report): `BannerAccessoryView.content`'s non-nil branch reverted to
    /// the self-owned-lease init (`BannerSlotView(isSuppressed:...)` with no
    /// `lease:` argument) — refresh count goes to 2 or the slot id changes.
    @Test("T2: the accessory's lease survives a push+pop re-host on its own tab")
    func accessorySurvivesPushPopReHost() async {
        let provider = FakeAdProvider()
        let session = makeOpenSession(provider: provider)
        let (window, viewModel) = makeHostedGameRoot(session: session)

        let becameVisible = await eventually { session.isVisible }
        #expect(becameVisible, "precondition: gate must be open")

        let reachedLoaded = await eventually {
            if case .loaded = session.slots.values.first { return true }
            return false
        }
        #expect(reachedLoaded, "precondition: the accessory's slot must load before probing re-host behavior")
        #expect(await provider.refreshCallCount == 1, "precondition: exactly one initial request")
        let initialID = session.slots.keys.first

        // Push then pop a route on the Today tab's own NavigationStack — the
        // #1080 probe's measured trigger set for a native re-host of
        // `tabViewBottomAccessory`'s content includes a push/pop pair.
        // Confirmed empirically (dispatch report): under the pre-fix
        // mutation this push/pop DOES flip the assertions below red, so the
        // harness genuinely reproduces a re-host rather than trivially
        // passing regardless of the fix.
        let path = viewModel.pathBinding(for: .today)
        path.wrappedValue.append(.first)
        window.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(200))
        path.wrappedValue.removeLast()
        window.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(400))

        #expect(session.slots.count == 1, "the push/pop must not register a second slot")
        #expect(session.slots.keys.first == initialID, "the push/pop must not change the slot id")
        #expect(await provider.refreshCallCount == 1, "the push/pop must not re-request the banner")
    }
}

#endif
