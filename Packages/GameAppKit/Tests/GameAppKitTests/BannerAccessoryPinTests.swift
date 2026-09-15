// BannerAccessoryPinTests — pin test for the shared banner accessory (#1080).
//
// PM requirement: the accessory's pre-#1080-merge render-level test suite
// (deleted during the #1062 rebase — see
// meetings/2026-09-07_1024-banner-accessory.impl-notes.md's "#1080
// follow-through") needed a replacement pin — an E2E-only pin does not
// count. This suite renders the REAL `GameRoot` (not a bare `RootShellView`)
// hosting the REAL `BannerAccessoryView` and drives it through an
// UN-started `BannerSessionModel` — `GameRoot.onAppear` is what calls
// `bannerSession.start()`, exactly like production (`MakeGameApp.swift`) —
// so the suite actually exercises the `bannerSession.isVisible` flip inside
// `GameRoot.shellContent`, not a value frozen at construction time (round-1
// gap: a bare `RootShellView` host never re-reads anything, so a regression
// hard-coding `bottomAccessoryIsEnabled` to either constant passed every
// round-1 test).
//
//   (a) gate open   → the accessory renders a registered slot that reaches
//       `.loaded`, not an empty capsule; the `\.bannerSession` injection
//       actually reaches the slot (no `onMissingSession` fallback); and
//       calling `session.dismiss()` afterward collapses the capsule again —
//       proving the true→false direction through Observation, not just the
//       initial render.
//   (b) gate denied → no accessory container at all (or a zero-height one
//       with no registered slot) once the (un-started, GameRoot-started)
//       session resolves `shouldShow == false`.
//   (c) macOS       → `makeBottomAccessory()` returns `EmptyView`,
//       STRUCTURALLY: `BannerAccessoryView` does not compile into the macOS
//       binary at all (mirrors GameShellKit's
//       `RootShellViewBottomAccessoryRenderTests`, which cannot even be
//       compiled on macOS for the same reason).
//
// Mutations, each named where it bites and EXECUTED red (then reverted) per
// PM instruction — a named-only mutation is weaker evidence than one run:
//   (a1) `BannerAccessoryView.body` → `EmptyView()` — (a) goes red (no
//        container, no registration).
//   (a2) drop `.environment(\.bannerSession, session)` from the hosting
//        helper — NOT executed: it mutates this test file's own helper, not
//        production, so it stays a named-only guard (the `onMissingSession`
//        assertion inside (a) is what it would trip).
//   (b)  `RootShellView.body`'s `.tabViewBottomAccessory(isEnabled:)` call
//        hard-coded to `true` — (b) goes red, and the dismiss half of (a)
//        goes red (the capsule survives `dismiss()`).
//   (c)  see above — structural, not a runtime mutation.
//   (d1) `GameRoot.shellContent`'s `bottomAccessoryIsEnabled:` hard-coded to
//        `true` — (b) goes red, and the dismiss half of (a) goes red.
//   (d2) `GameRoot.shellContent`'s `bottomAccessoryIsEnabled:` hard-coded to
//        `false` — (a) goes red (the capsule never appears at all).

#if os(macOS)

import SwiftUI
import Testing
@testable import GameAppKit

@MainActor
@Suite("Banner accessory pin (#1080)")
struct BannerAccessoryPinTests {

    @Test("(c) macOS: makeBottomAccessory() is structurally EmptyView")
    func macOSAccessoryIsStructurallyEmpty() {
        // Mutation: remove the `#if os(iOS)` guard inside `makeBottomAccessory`
        // (MakeGameApp+Helpers.swift) so both branches construct
        // `BannerAccessoryView()`. On macOS that mutation doesn't just make
        // this test red — `BannerAccessoryView` (and the `BannerSlotView` it
        // wraps) is itself gated `#if os(iOS)`, so the type doesn't exist on
        // this platform at all and the macOS build fails outright. That
        // build failure IS the structural exclusion this test stands in for.
        #expect((makeBottomAccessory() as Any) is EmptyView)
    }
}

#endif

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

// MARK: - Sentinel route/factory
//
// A private copy, not shared with GameShellKit's
// `RootShellViewBottomAccessoryRenderTests` — per instruction, GameShellKit's
// test helpers stay test-only and unshared across packages.

private enum AccessoryPinSentinelRoute: Hashable, Sendable {
    case first
    case settings
}

private struct AccessoryPinSentinelFactory: RouteFactory {
    typealias Route = AccessoryPinSentinelRoute

    @MainActor
    func view(for route: AccessoryPinSentinelRoute, path: Binding<[AccessoryPinSentinelRoute]>?) -> AnyView {
        AnyView(Text("destination"))
    }
}

// MARK: - GameRootViewModel doubles
//
// Private copies of `TodayTabHostTests`' `ATTHostStubPersistence` /
// `ATTHostStubGameCenter` (that file's are `private`, so not importable) —
// the minimal stubs needed to construct a real `GameRootViewModel` whose
// `bootstrap()` (called from `GameRoot.onAppear`) completes instantly and
// harmlessly.

private actor AccessoryPinStubPersistence: PersistenceProtocol {
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

private struct AccessoryPinStubGameCenter: GameCenterClient {
    func authenticate() async throws -> GameCenterAuthState { .unauthenticated }
    func authStateUpdates() async -> AsyncStream<GameCenterAuthState> {
        AsyncStream { $0.finish() }
    }
    func submitScore(puzzleId: String, elapsedSeconds: Int, leaderboardKind: LeaderboardKind) async throws {}
    func submitScore(leaderboardId: String, elapsedSeconds: Int) async throws {}
    func reportAchievement(_ achievement: AchievementProgress) async throws {}
}

// MARK: - Container-walking helpers
//
// Private copies of GameShellKit's `findAccessoryContainer` /
// `waitForAccessoryContainer` (RootShellViewBottomAccessoryRenderTests.swift)
// — same proof strategy (SwiftUI mounts `tabViewBottomAccessory`'s content
// inside a private container view whose class name contains
// "BottomAccessory"), not exported across packages.

@MainActor
private func findAccessoryContainer(in view: UIView) -> UIView? {
    if String(describing: type(of: view)).contains("BottomAccessory") {
        return view
    }
    for subview in view.subviews {
        if let found = findAccessoryContainer(in: subview) {
            return found
        }
    }
    return nil
}

@MainActor
private func waitForAccessoryContainer(in window: UIWindow) async -> UIView? {
    var iterations = 0
    while iterations < 50 {
        if let container = findAccessoryContainer(in: window) {
            return container
        }
        try? await Task.sleep(for: .milliseconds(20))
        iterations += 1
    }
    return nil
}

/// Polls `condition` every 10ms until it holds or `timeout` elapses (mirrors
/// `TodayTabHostTests.eventually`).
@MainActor
private func eventually(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        if ContinuousClock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

// MARK: - Session + hosted-GameRoot helpers

/// A `BannerSessionModel` whose gate is open or denied — NOT started here.
/// `GameRoot.onAppear` is the one that calls `start()`, mirroring
/// production exactly (`MakeGameApp.swift`). Denied via
/// `hasPurchasedRemoveAds` — the highest-precedence, `now`-independent
/// `AdGate` rule (`AdGate.swift` resolution order, rule 1).
@MainActor
private func makeSession(gateOpen: Bool) -> BannerSessionModel {
    let state = AdGateState(
        firstLaunchAt: Date(timeIntervalSince1970: 0),
        hasPurchasedRemoveAds: !gateOpen
    )
    let adGate = AdGate(store: FakeAdGateStateStore(initial: state))
    return BannerSessionModel(adProvider: FakeAdProvider(), adGate: adGate)
}

/// Hosts the REAL `GameRoot` — same shape `makeGameAppCore` builds
/// (`MakeGameApp.swift`): `GameRoot(...)` then `.environment(\.bannerSession,
/// session)` on the `GameRoot` value itself, with `bottomAccessory: {
/// makeBottomAccessory() }` supplying the REAL `BannerAccessoryView` on iOS.
/// `session` must not already be started — `GameRoot.onAppear` does that.
@MainActor
private func makeHostedGameRoot(session: BannerSessionModel) -> UIWindow {
    let viewModel = GameRootViewModel<AccessoryPinSentinelRoute>(
        gameCenter: AccessoryPinStubGameCenter(),
        persistence: AccessoryPinStubPersistence()
    )
    let root = GameRoot(
        viewModel: viewModel,
        bannerSession: session,
        routeFactory: AccessoryPinSentinelFactory(),
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
    return window
}

// MARK: - Suite
//
// `.serialized`: test (a) temporarily swaps the static
// `BannerSessionModel.onMissingSession` hook to observe it, then restores
// the original — that mutable static must not race a concurrently-running
// test in this suite.

@MainActor
@Suite("Banner accessory pin (#1080)", .serialized)
struct BannerAccessoryPinTests {

    @Test("(a) gate open: accessory renders a loaded slot, then hides on dismiss")
    func gateOpenRendersThenHidesOnDismiss() async {
        let session = makeSession(gateOpen: true)

        // Prove the `\.bannerSession` injection actually reaches the slot —
        // mutation (a2, named-only, see file header): dropping
        // `.environment(\.bannerSession, session)` from the hosting helper
        // would make `BannerSlotRegistration` call `onMissingSession()`
        // instead of registering. Swap + restore the static hook around the
        // render.
        let originalOnMissingSession = BannerSessionModel.onMissingSession
        var missingSessionCalled = false
        BannerSessionModel.onMissingSession = { missingSessionCalled = true }
        defer { BannerSessionModel.onMissingSession = originalOnMissingSession }

        let window = makeHostedGameRoot(session: session)

        // Nothing here calls `session.start()` — only `GameRoot.onAppear`
        // does. Mutation (d2): `bottomAccessoryIsEnabled:` hard-coded false
        // makes `becameVisible` never resolve.
        let becameVisible = await eventually { session.isVisible }
        #expect(becameVisible, "GameRoot.onAppear must start() the session and flip isVisible true when the gate is open")

        let container = await waitForAccessoryContainer(in: window)
        #expect(
            !missingSessionCalled,
            "mutation (a2): the \\.bannerSession injection was dropped — the slot fell back to onMissingSession()"
        )

        guard let container else {
            Issue.record("no tabViewBottomAccessory container ever appeared — mutation (a1) or (d2)")
            return
        }
        #expect(
            container.bounds.height > 0 && !container.subviews.isEmpty,
            "accessory container present but empty/zero-height — mutation (a1): BannerAccessoryView.body reverted to EmptyView()"
        )

        let registered = await eventually { session.slots.count == 1 }
        #expect(
            registered,
            "expected exactly one registered slot — the accessory's BannerSlotView never registered (currently: \(session.slots.count))"
        )

        let reachedLoaded = await eventually {
            if case .loaded = session.slots.values.first { return true }
            return false
        }
        #expect(
            reachedLoaded,
            "registered slot never reached .loaded — got \(session.slots.values.first.map { String(describing: $0) } ?? "none")"
        )

        // Prove true→false through Observation, not just the initial
        // render. Mutations (b) and (d1) — `isEnabled`/`bottomAccessoryIsEnabled`
        // hard-coded `true` — leave the capsule up after dismiss.
        await session.dismiss()
        let hiddenAfterDismiss = await eventually {
            let liveContainer = findAccessoryContainer(in: window)
            return liveContainer == nil || (liveContainer!.bounds.height == 0 && liveContainer!.subviews.isEmpty)
        }
        #expect(
            hiddenAfterDismiss,
            "capsule survived dismiss() — mutation (b): RootShellView isEnabled hard-coded true, or (d1): GameRoot bottomAccessoryIsEnabled hard-coded true"
        )
    }

    @Test("(b) gate denied: no accessory capsule and no registered slot")
    func gateDeniedRendersNothing() async {
        let session = makeSession(gateOpen: false)
        let window = makeHostedGameRoot(session: session)

        // Mutation (d1): `bottomAccessoryIsEnabled:` hard-coded true makes
        // `shouldShow` still resolve false (the gate itself is untouched by
        // that mutation) but the capsule below would incorrectly render.
        let resolved = await eventually { session.shouldShow == false }
        #expect(resolved, "GameRoot.onAppear must start() the session and resolve shouldShow to false when the gate is denied")

        _ = await waitForAccessoryContainer(in: window)
        let container = findAccessoryContainer(in: window)

        #expect(
            container == nil || (container!.bounds.height == 0 && container!.subviews.isEmpty),
            "mutation (b): RootShellView isEnabled hard-coded true, or (d1): GameRoot bottomAccessoryIsEnabled hard-coded true"
        )
        #expect(session.slots.isEmpty, "no slot should hold load state while the accessory never mounted a visible BannerSlotView")
    }
}

#endif
