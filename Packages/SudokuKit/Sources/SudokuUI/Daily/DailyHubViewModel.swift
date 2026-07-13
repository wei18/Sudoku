// DailyHubViewModel — owns trio fetch + completion overlay.
//
// Per docs/designs/03-daily-hub.md + docs/v1/design.md §How.5.4. Bootstraps by
// fetching today's trio from PuzzleProvider and the already-completed
// daily puzzleIds from Persistence; merges them into 3 `DailyCard` rows.

public import Foundation
public import SwiftUI
import GameShellUI
public import SudokuPersistence
public import Persistence
public import SudokuEngine
public import Telemetry

public struct DailyCard: Sendable, Equatable, Hashable, Identifiable {
    public let envelope: PuzzleEnvelope
    public let isCompleted: Bool

    public var id: String { envelope.identity.puzzleId }
    public var difficulty: Difficulty { envelope.identity.difficulty }
}

public enum DailyHubState: Sendable, Equatable {
    case idle
    case loading
    case loaded([DailyCard])
    case exhausted
    case failed(String)
}

@MainActor
@Observable
public final class DailyHubViewModel {
    public private(set) var state: DailyHubState = .idle

    /// Navigation path store (issue #240): routes through an injected
    /// `Binding<[AppRoute]>` when `RouteFactory` hoists `RootViewModel.path`
    /// via `init(path:)`, otherwise a local stub (previews / unit tests).
    /// Mirrors `HomeViewModel`'s pattern (issue #197).
    private var routePath: RoutePath<AppRoute>

    /// Single public view of the navigation path. Callers do not need to know
    /// which mode (injected binding / local stub) is active.
    public var path: [AppRoute] {
        get { routePath.effectivePath }
        set { routePath.effectivePath = newValue }
    }

    private let provider: any PuzzleProviderProtocol
    private let persistence: any PersistenceProtocol
    private let errorReporter: any ErrorReporter
    private let dateProvider: @Sendable () -> Date
    /// Idempotency latch for `.task` — once `bootstrap()` has resolved we
    /// don't re-enter the fetch path on subsequent SwiftUI lifecycle ticks.
    private var hasBootstrapped = false

    /// Transient in-flight latch for the completed-card → Completion fan-out
    /// (#385). `cardTapped` is a synchronous `@MainActor` closure, so a
    /// double-tap (or a tap landing during the in-flight `loadOrCreate`) can
    /// otherwise push `.completion` twice. Set synchronously before spawning
    /// the open Task and cleared in `openCompleted`'s `defer` — both run on
    /// the MainActor, so no second tap can slip a route in during the load.
    /// Unlike BoardView's completion-overlay presentation (a one-shot
    /// `.completed` transition, #667), this RESETS so a re-tap after
    /// returning to the hub works again.
    private var isOpeningCompleted = false

    public init(
        provider: any PuzzleProviderProtocol,
        persistence: any PersistenceProtocol,
        errorReporter: any ErrorReporter = NoopErrorReporter(),
        dateProvider: @escaping @Sendable () -> Date = { Date() },
        path: Binding<[AppRoute]>? = nil
    ) {
        self.provider = provider
        self.persistence = persistence
        self.errorReporter = errorReporter
        self.dateProvider = dateProvider
        self.routePath = RoutePath(path)
    }

    public func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        let today = dateProvider()
        // Two-phase orchestration delegated to the shared skeleton (#558).
        // Phase-1 fetches the trio and renders immediately (no CK dependency).
        // Phase-2 fills the completion overlay asynchronously — best-effort,
        // never blocks the initial render (M10 / §How.6.1 p1).
        await performDailyBootstrap(
            setLoading: { state = .loading },
            fetchPhase1: { try await self.provider.fetchDailyTrio(date: today) },
            onPhase1: { trio in
                // Phase 1: render immediately with completion unknown (#526).
                let cards = trio.map { DailyCard(envelope: $0, isCompleted: false) }
                state = .loaded(cards)
            },
            // async closures require explicit `self.` under Swift 6 strict
            // concurrency (the sync closures above legitimately omit it).
            onPhase1Error: { error in
                if let puzzleError = error as? PuzzleStoreError,
                   case .generatorFailed = puzzleError {
                    self.state = .exhausted
                } else {
                    await self.errorReporter.report(
                        UserFacingError.classify(error),
                        underlying: error,
                        source: "DailyHubViewModel.bootstrap"
                    )
                    self.state = .failed(String(describing: error))
                }
            },
            fetchPhase2: { trio in
                // Phase 2: completion overlay — non-blocking, best-effort.
                await self.fillCompletionOverlay(trio: trio, date: today)
            }
        )
    }

    /// Re-runs the phase-2 completion-overlay fetch outside `bootstrap()`'s
    /// one-shot gate (#761), mirroring how `GameRootViewModel.refreshResumeCandidate()`
    /// bypasses `bootstrap()`'s own gate for the resume pill. Closing the
    /// Completion overlay after solving a daily returns to this same,
    /// un-destroyed hub instance — nothing re-triggered a load, so the
    /// just-solved card stayed unchecked until the whole hub was torn down and
    /// remounted.
    ///
    /// Called from `DailyHubView`'s `.onChange(of: sessionTeardownCount)` —
    /// `GameRoot`'s explicit game-session-teardown signal (#761). An earlier
    /// version of this fix rode `.onAppear`, on the theory that it re-fires
    /// whenever the hub becomes visible again; simulator verification disproved
    /// that for the real Close → Leave flow (a dismissing `fullScreenCover`
    /// does not re-fire the covered view's `.onAppear` at all — the only
    /// re-fire is a transient push-pop at board OPEN, which is useless here
    /// since completion doesn't exist yet).
    ///
    /// Re-fetches only completed ids, not the trio (today's puzzles never
    /// change) — cheap, like `refreshResumeCandidate`'s single query. The
    /// `hasBootstrapped` + `.loaded` guard below still protects against
    /// running before `bootstrap()`'s phase-1 has landed.
    public func refresh() async {
        guard hasBootstrapped, case .loaded(let cards) = state else { return }
        await fillCompletionOverlay(trio: cards.map(\.envelope), date: dateProvider())
    }

    /// Phase-2 completion overlay: fetches completed daily ids and re-merges
    /// them with the already-rendered cards. Called after `state` is already
    /// `.loaded` so a hang or failure here cannot block the initial render.
    /// Errors are funneled through `errorReporter` (OSLog-observable) and
    /// degrade silently to "no cards completed" — same M10 contract as before.
    /// Also the target of `refresh()`'s re-fetch (#761).
    private func fillCompletionOverlay(trio: [PuzzleEnvelope], date: Date) async {
        // #788: guard `.loaded` before AND after the fetch — mirrors MS's
        // `fillCompletionAndFailureOverlay`. Since #761 this method is
        // re-entrant via `refresh()` (the session-teardown signal), so a state
        // transition landing mid-fetch must not resurrect a stale `.loaded`
        // write over whatever state replaced it.
        guard case .loaded = state else { return }
        let completed: Set<String>
        do {
            completed = try await persistence.fetchCompletedDailyIds(for: date)
        } catch {
            await errorReporter.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "DailyHubViewModel.fetchCompletedDailyIds"
            )
            return // degrade: cards remain un-completed
        }
        guard case .loaded = state else { return }
        guard !completed.isEmpty else { return }
        let cards = trio.map { envelope in
            DailyCard(envelope: envelope, isCompleted: completed.contains(envelope.identity.puzzleId))
        }
        state = .loaded(cards)
    }

    /// Synchronous tap entry point (the DailyHubView shell closure is sync).
    /// An un-completed card pushes straight to the board. A completed card
    /// (#379) must re-surface the player's result, so it fans out to the
    /// async `openCompleted(_:)` helper which fetches the frozen solve time
    /// and routes to `.completion`. The helper is `await`-able directly so
    /// tests don't depend on fire-and-forget `Task` timing.
    public func cardTapped(_ card: DailyCard) {
        guard card.isCompleted else {
            path.append(.board(puzzleId: card.envelope.identity.puzzleId))
            return
        }
        // #385: drop re-taps while a previous open is still in flight so the
        // async fan-out can't push `.completion` twice. The `.board` branch
        // above is synchronous and not latched (unchanged prior behavior).
        guard !isOpeningCompleted else { return }
        isOpeningCompleted = true
        Task { await openCompleted(card) }
    }

    /// Loads the completed daily's saved snapshot to recover its frozen
    /// `elapsedSeconds`, then routes to the Completion screen. On a load
    /// failure we report through the funnel and fall back to `.board` — never
    /// worse than the pre-#379 behavior, and never silently stuck.
    /// #686: the `.exhausted` alert's primary CTA. The Daily hub has no
    /// difficulty picker of its own — the Practice hub does — so "try
    /// another difficulty" routes there. The hub was PUSHED from Home, so
    /// swapping the last path entry (`.daily` → `.practice`) is the clean
    /// move; it replaces the dead-end screen instead of stacking a second
    /// push on top of it.
    public func tryPracticeInstead() {
        if !path.isEmpty {
            path[path.count - 1] = .practice
        } else {
            path.append(.practice)
        }
    }

    /// #686: the `.exhausted` alert's dismiss CTA. A `.exhausted` hub has
    /// nothing to show, so staying on it after dismiss is the second half of
    /// the trap the alert used to leave the user in — pop back to Home
    /// instead of a blank backdrop.
    public func dismissExhausted() {
        if !path.isEmpty {
            path.removeLast()
        }
    }

    func openCompleted(_ card: DailyCard) async {
        // Reset on both success and the error/fallback path so a later tap
        // (#385) re-enters cleanly. `@MainActor` guarantees this runs without
        // an interleaved `cardTapped` between the route append and the clear.
        defer { isOpeningCompleted = false }
        let puzzleId = card.envelope.identity.puzzleId
        do {
            let snapshot = try await persistence.loadOrCreate(
                puzzleId: puzzleId,
                mode: .daily,
                difficulty: card.difficulty
            )
            path.append(.completion(
                puzzleId: puzzleId,
                elapsedSeconds: snapshot.elapsedSeconds,
                mistakeCount: snapshot.mistakeCount
            ))
        } catch {
            await errorReporter.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "DailyHubViewModel.openCompleted"
            )
            path.append(.board(puzzleId: puzzleId))
        }
    }
}
