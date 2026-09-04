// DailyHubViewModel — owns trio fetch + completion overlay.
//
// Per docs/designs/03-daily-hub.md + docs/v1/design.md §How.5.4. Bootstraps by
// fetching today's trio from PuzzleProvider and the already-completed
// daily puzzleIds from Persistence; merges them into 3 `DailyCard` rows.

public import Foundation
public import SwiftUI
// #1020: public — `AppTab` (the `selectTab` param type) is in the public init.
public import GameShellUI
public import SudokuPersistence
public import Persistence
public import SudokuEngine
public import Telemetry

public struct DailyCard: Sendable, Equatable, Hashable, Identifiable {
    public let envelope: PuzzleEnvelope
    public let isCompleted: Bool
    /// #886: this difficulty's best DAILY time (`Mode.daily`, ALL-time across
    /// every day, not just today's puzzle) — `nil` while unfetched, unknown,
    /// or genuinely never completed; all three degrade to the same "—" in
    /// `DailyPuzzleCard`. Defaulted so existing call sites compile unchanged.
    public let bestTimeSeconds: Int?

    public var id: String { envelope.identity.puzzleId }
    public var difficulty: Difficulty { envelope.identity.difficulty }

    public init(envelope: PuzzleEnvelope, isCompleted: Bool, bestTimeSeconds: Int? = nil) {
        self.envelope = envelope
        self.isCompleted = isCompleted
        self.bestTimeSeconds = bestTimeSeconds
    }
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
    /// #774: the rolling 7-day week strip + streak. `.unknown` (empty days,
    /// nil streak) until the first successful `fetchWeekWindow` — see
    /// `fillCompletionOverlay`, which is this state's sole writer (same
    /// method that already drives the trio's completion overlay, so both
    /// share the same CK round-trips and the same #761 `refresh()` re-entry).
    public private(set) var weekStrip: DailyStripSnapshot = .unknown
    /// #826: non-nil while the confirmationDialog picker is showing (a
    /// tapped past day had more than one completed difficulty). `DailyHubView`
    /// binds its `.confirmationDialog(isPresented:)` to `!= nil` and calls
    /// `reviewChoiceSelected(_:)` / `dismissReviewPicker()`. #1021 Phase B:
    /// `internal(set)` (was `private(set)`) so `DailyHubViewModel+Review.swift`
    /// (split out to keep this file under the 400-line `file_length` ceiling)
    /// can write it.
    public internal(set) var reviewPickerChoices: [DailyReviewChoice]?

    /// #1021 Phase B: all-time completed days, feeding `TodayMapper`'s
    /// `longest` streak. See `DailyHubViewModel+Today.swift`.
    private(set) var allCompletedDays: Set<DayKey> = []
    /// #1021 Phase B: best-effort in-progress save for `TodayMapper`. See
    /// `DailyHubViewModel+Today.swift`.
    private(set) var inProgressSummary: SavedGameSummary?

    /// #842: `true` from `.loaded`'s first render until `fillCompletionOverlay`
    /// (phase 2 — the completion overlay fetch) resolves at least once, for
    /// EITHER `bootstrap()`'s initial run or a later `refresh()` re-entry.
    /// #941 (owner-requested, reverses #842/#878): neither `cardTapped` nor
    /// `DailyPuzzleCard` reads this anymore — a tap routes off `card`'s
    /// current data even while `true`, and the card stays full-opacity +
    /// `.isButton`. Safe because correctness was always `BoardLoaderView`'s
    /// precheck, not this flag. Kept `internal` purely so tests can still
    /// observe the in-flight window. #905: `+Testing.swift` seeds it.
    var isPhase2Pending = true

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
    // #886: `internal` (not `private`) so `DailyHubViewModel+BestTime.swift`
    // (split out purely to keep this file under the 400-line `file_length`
    // ceiling — same rationale as `MinesweeperGameViewModel+SubmitOnWin.swift`)
    // can read them.
    let persistence: any PersistenceProtocol
    let errorReporter: any ErrorReporter
    private let dateProvider: @Sendable () -> Date
    /// #1020: the exhausted block's "Practice" CTA switches tabs now instead
    /// of pushing a `.practice` route (design.md §3.1). No-op default keeps
    /// tests/previews that don't wire a root VM working.
    private let selectTab: @MainActor (AppTab) -> Void
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
    /// returning to the hub works again. #1021 Phase B: not `private` —
    /// `DailyHubViewModel+Review.swift` writes it too.
    var isOpeningCompleted = false

    public init(
        provider: any PuzzleProviderProtocol,
        persistence: any PersistenceProtocol,
        errorReporter: any ErrorReporter = NoopErrorReporter(),
        dateProvider: @escaping @Sendable () -> Date = { Date() },
        path: Binding<[AppRoute]>? = nil,
        selectTab: @escaping @MainActor (AppTab) -> Void = { _ in }
    ) {
        self.provider = provider
        self.persistence = persistence
        self.errorReporter = errorReporter
        self.dateProvider = dateProvider
        self.routePath = RoutePath(path)
        self.selectTab = selectTab
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

    /// Phase-2 completion overlay: fetches the rolling 7-day completed-ids
    /// window and re-merges it with the already-rendered cards (today's
    /// slot) AND the week strip (all 7 slots). Called after `state` is
    /// already `.loaded` so a hang or failure here cannot block the initial
    /// render. Errors are funneled through `errorReporter` (OSLog-observable)
    /// and degrade silently — same M10 contract as before. Also the target
    /// of `refresh()`'s re-fetch (#761).
    ///
    /// #774: today's slot in the fetched window is reused for the trio-card
    /// overlay instead of issuing a second, duplicate `fetchCompletedDailyIds`
    /// call for the same date — the dispatch spec's "×7 total" fetch budget
    /// (not "×7 in addition to the existing 1") depends on this reuse.
    private func fillCompletionOverlay(trio: [PuzzleEnvelope], date: Date) async {
        // #842: re-armed on every entry (bootstrap AND refresh) and cleared via
        // `defer` regardless of which return path fires below — the tap gate
        // must cover a `refresh()` re-fetch window too (e.g. returning to the
        // hub right after a solve), not just the very first bootstrap.
        isPhase2Pending = true
        defer { isPhase2Pending = false }
        // #788: guard `.loaded` before AND after the fetch — mirrors MS's
        // `fillCompletionAndFailureOverlay`. Since #761 this method is
        // re-entrant via `refresh()` (the session-teardown signal), so a state
        // transition landing mid-fetch must not resurrect a stale `.loaded`
        // write over whatever state replaced it.
        guard case .loaded = state else { return }
        // #886: the per-difficulty best-time read rides this same phase-2
        // window, in parallel with the week-window fetch (`async let` — two
        // independent CK read lanes, no ordering dependency). Production
        // `PrivateCKGateway` conformers are plain actors — concurrent calls
        // just serialize at the mailbox, never deadlock; a round-1 attempt
        // sequentialized this needlessly after misreading a single-
        // continuation TEST FAKE limitation (`GatedQueryGateway`, since fixed
        // to queue multiple pending continuations) as a production hazard.
        // Best-time failures are scoped per difficulty (`fetchBestTimes`'s
        // own try/catch), unlike the week window's all-or-nothing degrade —
        // never blocks or degrades the window/strip below.
        async let windowTask = fetchWeekWindow(referenceDate: date)
        async let bestTimesTask = fetchBestTimes(trio: trio)
        // #1021 Phase B: independent best-effort lane — see `fetchInProgressSummary`.
        async let inProgressTask = fetchInProgressSummary()
        let window = await windowTask
        let bestTimes = await bestTimesTask
        inProgressSummary = await inProgressTask
        guard case .loaded(let latestCards) = state else { return }
        // Best times always merge in, even on a week-window degrade (no
        // false-claim risk — see above). `isCompleted` falls back to the
        // card's current value on a window-fetch failure, matching the
        // pre-#886 degrade behavior below.
        let todayCompleted = window?.slots.first { $0.offsetFromToday == 0 }?.completedPuzzleIds
        state = .loaded(latestCards.map { card in
            DailyCard(
                envelope: card.envelope,
                isCompleted: todayCompleted?.contains(card.envelope.identity.puzzleId) ?? card.isCompleted,
                bestTimeSeconds: bestTimes[card.difficulty]
            )
        })
        guard let window else {
            // #774: any single day's fetch failing degrades the WHOLE window
            // rather than risk showing a wrong "missed" dot for a day whose
            // fetch actually failed — see `fetchWeekWindow`.
            weekStrip = .unknown
            allCompletedDays = []
            return // degrade: strip unknown; cards keep prior completion + fresh best times (above)
        }
        // No re-check of `.loaded` here — no `await` separates the write above from this point.
        let days = window.slots.map { slot in
            DailyStripDay(
                offsetFromToday: slot.offsetFromToday,
                date: slot.date,
                isCompleted: !slot.completedPuzzleIds.isEmpty,
                completedPuzzleIds: slot.completedPuzzleIds
            )
        }
        let rawStreak = DailyStripLogic.computeStreak(days: days)
        weekStrip = DailyStripSnapshot(days: days, streak: rawStreak > 0 ? rawStreak : nil)
        // #1021 Phase B: reuses the SAME fetched dictionary, not a second fetch.
        allCompletedDays = Self.completedDays(from: window.completedByDay)
    }

    /// Synchronous tap entry point (the DailyHubView shell closure is sync).
    /// An un-completed card pushes straight to the board. A completed card
    /// (#379) must re-surface the player's result, so it fans out to the
    /// async `openCompleted(_:)` helper which fetches the frozen solve time
    /// and routes to `.completion`. The helper is `await`-able directly so
    /// tests don't depend on fire-and-forget `Task` timing.
    public func cardTapped(_ card: DailyCard) {
        // #941: the #842 `isPhase2Pending` tap gate is gone — a tap routes
        // optimistically off whatever `card.isCompleted` currently says, even
        // mid-fetch. Correctness is `BoardLoaderView`'s job — see
        // `isPhase2Pending`'s doc.
        guard card.isCompleted else {
            path.append(.board(puzzleId: card.envelope.identity.puzzleId))
            return
        }
        // #385: drop re-taps while a previous open is still in flight so the
        // async fan-out can't push `.completion` twice. The `.board` branch
        // above is synchronous and not latched (unchanged prior behavior).
        guard !isOpeningCompleted else { return }
        isOpeningCompleted = true
        Task { await openCompleted(puzzleId: card.envelope.identity.puzzleId, difficulty: card.difficulty) }
    }

    /// #686: the `.exhausted` alert's primary CTA — routes to Practice (its
    /// difficulty picker), since the Daily hub has none of its own. #1020
    /// (design.md §3.1): Practice is a tab now, not a `.practice` route to
    /// swap the path to — switch tabs via the injected `selectTab` closure.
    public func tryPracticeInstead() {
        selectTab(.practice)
    }

    /// #686/#1020 (design.md §3.1, exhausted row): the dismiss CTA. Today is
    /// the tab root now, not a route pushed from Home — "Cancel" closes the
    /// block by dropping to an empty `.loaded` state and stays on Today.
    public func dismissExhausted() {
        guard case .exhausted = state else { return }
        state = .loaded([])
    }

    // `dayTapped` / `reviewChoiceSelected` / `dismissReviewPicker` /
    // `openReview` / `openCompleted` — the past-day review flow (#826/#830) —
    // moved to `DailyHubViewModel+Review.swift` (#1021 Phase B, purely to
    // keep this file under the 400-line `file_length` ceiling).
}
