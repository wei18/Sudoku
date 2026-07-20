// MinesweeperDailyHubViewModel — owns the daily trio fetch + completion overlay.
//
// Mirrors `SudokuUI.DailyHubViewModel`: bootstraps by fetching today's trio
// from a `MinesweeperDailyProviding` and the already-completed/failed daily
// ids from `MinesweeperSavedGameStore`, merging them into three
// `MinesweeperDailyCard` rows. The overlay fetch is graceful-degrade (a
// failure renders every card un-completed, never blocks the hub) — same
// principle as Sudoku's Daily.
//
// MS generation is synchronous + non-throwing (pure `MinesweeperDaily`), so
// there is no `.exhausted` / generator-failure path; the only async work is
// the optional completed/failed-ids fetch.
//
// #816: the completed-ids fetch used to go through the Sudoku-shaped
// `PersistenceProtocol.fetchCompletedDailyIds` — a CK predicate that assumes
// a `puzzleId` field MS's `SavedGame` schema doesn't have, so it always threw
// and the green check never appeared. It now reads from
// `MinesweeperSavedGameStore.fetchCompletedDailyIds`, mirroring the
// already-working failed-ids path below.

public import Foundation
public import SwiftUI
import GameShellUI
public import MinesweeperEngine
public import MinesweeperPersistence
public import Persistence
public import Telemetry

public struct MinesweeperDailyCard: Hashable, Sendable, Identifiable {
    public let entry: MinesweeperDailyEntry
    public let isCompleted: Bool
    /// Epic 8 (SDD-003): `true` when the player hit a mine on this daily — a
    /// third state distinct from completed (won) and not-yet-played. A failed
    /// daily can be replayed freely but the replay is unscored and does not
    /// change this record.
    public let isFailed: Bool
    /// #886: this difficulty's best DAILY time (`modeRaw: "daily"`, ALL-time
    /// across every day, not just today's board) — `nil` while unfetched,
    /// unknown, or genuinely never completed; all three degrade to the same
    /// "—" in `MinesweeperDailyCardView`. Defaulted so existing call sites
    /// (phase-1 render, tests, previews) compile unchanged. Mirrors Sudoku's
    /// `DailyCard.bestTimeSeconds`.
    public let bestTimeSeconds: Int?

    public var id: String { entry.puzzleId }
    public var difficulty: Difficulty { entry.difficulty }
    public var seed: UInt64 { entry.seed }

    public init(entry: MinesweeperDailyEntry, isCompleted: Bool, isFailed: Bool = false, bestTimeSeconds: Int? = nil) {
        self.entry = entry
        self.isCompleted = isCompleted
        self.isFailed = isFailed
        self.bestTimeSeconds = bestTimeSeconds
    }
}

public enum MinesweeperDailyHubState: Sendable, Equatable {
    case idle
    case loading
    case loaded([MinesweeperDailyCard])
}

@MainActor
@Observable
public final class MinesweeperDailyHubViewModel {
    /// #905: `internal(set)` (was `private(set)`) so `+Testing.swift` — split
    /// out to mirror `SudokuUI.DailyHubViewModel+Testing`'s shape — can seed it.
    public internal(set) var state: MinesweeperDailyHubState = .idle
    /// #774: the rolling 7-day week strip + streak. `.unknown` (empty days,
    /// nil streak) until the first successful `fetchWeekWindow` — see
    /// `fillCompletionAndFailureOverlay`, which is this state's sole writer.
    /// #905: `internal(set)` (was `private(set)`) so `+Testing.swift` can seed it.
    public internal(set) var weekStrip: MinesweeperDailyStripSnapshot = .unknown
    /// #826: non-nil while the confirmationDialog picker is showing. Mirrors
    /// `SudokuUI.DailyHubViewModel.reviewPickerChoices`.
    public private(set) var reviewPickerChoices: [MinesweeperDailyReviewChoice]?

    /// #842: `true` from `.loaded`'s first render until
    /// `fillCompletionAndFailureOverlay` (phase 2) resolves at least once, for
    /// EITHER `bootstrap()`'s initial run or a later `refresh()` re-entry.
    /// `cardTapped` no-ops while this is `true` — mirrors
    /// `SudokuUI.DailyHubViewModel.isPhase2Pending` exactly. Correctness
    /// (never mounting a scored/playable board for an actually completed or
    /// failed daily) is `MinesweeperDailyOpenGuardView`'s job even when this
    /// gate is bypassed or races closed anyway — this is the UX-responsiveness
    /// half of the #842 defense-in-depth pair, not the airtight half.
    /// #905: `internal` (not `public`) — only `MinesweeperDailyHubView` (this
    /// module) and `@testable`-importing test targets read/write it.
    var isPhase2Pending = true

    private var path: Binding<[AppRoute]>

    private let provider: any MinesweeperDailyProviding
    /// #816: retained for source compatibility with existing call sites, but
    /// no longer read by `fillCompletionAndFailureOverlay` — the completed-ids
    /// fetch moved to `savedGameStore.fetchCompletedDailyIds` (the generic
    /// `PersistenceProtocol.fetchCompletedDailyIds` predicate assumes a
    /// `puzzleId` field MS's schema doesn't have). Param removal is deferred
    /// (no scope creep in the #816 fix); a follow-up can drop it.
    private let persistence: (any PersistenceProtocol)?
    /// MS-native store for both the failed-daily (Epic 8 / SDD-003) and,
    /// since #816, the completed-daily ids fetch. Optional so preview / test
    /// callsites that don't thread a store keep compiling — when nil, no
    /// cards are ever marked completed or failed (graceful-degrade).
    /// `internal` (not `private`) so `MinesweeperDailyHubViewModel+Overlay.swift`
    /// (split out purely to keep this file under the 400-line `file_length`
    /// ceiling — same rationale as `MinesweeperGameViewModel+SubmitOnWin.swift`)
    /// can read it.
    let savedGameStore: MinesweeperSavedGameStore?
    /// #886: per-difficulty best-DAILY-time reads
    /// (`fetch(modeRaw: "daily", difficulty:)`) — the same store
    /// `MinesweeperStatsViewModel` already reads for the Stats screen's Daily
    /// section, zero new Persistence surface. Optional so preview / test
    /// callsites that don't thread a store keep compiling — when nil, every
    /// card's `bestTimeSeconds` stays `nil` (renders "—", never blocks).
    let personalRecordStore: MinesweeperPersonalRecordStore?
    let errorReporter: any ErrorReporter
    private let dateProvider: @Sendable () -> Date
    /// Idempotency latch for `.task` — once `bootstrap()` resolves we don't
    /// re-enter the fetch path on subsequent SwiftUI lifecycle ticks.
    /// #905: `internal` (was `private`) — Swift access control requires a
    /// stored property's getter to be at least as visible as its setter, and
    /// `+Testing.swift`'s `setStateForTesting` needs to write it from another
    /// file in this module.
    var hasBootstrapped = false

    public init(
        path: Binding<[AppRoute]>,
        provider: any MinesweeperDailyProviding = LiveMinesweeperDailyProvider(),
        persistence: (any PersistenceProtocol)? = nil,
        savedGameStore: MinesweeperSavedGameStore? = nil,
        personalRecordStore: MinesweeperPersonalRecordStore? = nil,
        errorReporter: any ErrorReporter = NoopErrorReporter(),
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.path = path
        self.provider = provider
        self.persistence = persistence
        self.savedGameStore = savedGameStore
        self.personalRecordStore = personalRecordStore
        self.errorReporter = errorReporter
        self.dateProvider = dateProvider
    }

    // #905: the `setStateForTesting` / `setWeekStripForTesting` /
    // `setPhase2PendingForTesting` test-only seams that used to live here
    // moved to `MinesweeperDailyHubViewModel+Testing.swift`, mirroring
    // `SudokuUI.DailyHubViewModel`'s `+Testing.swift` split.

    public func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        let today = dateProvider()
        // Two-phase orchestration delegated to the shared skeleton (#558).
        // `dailyTrio` is synchronous and non-throwing — phase-1 wraps it in an
        // async closure that can never throw, so onPhase1Error is unreachable.
        // Phase-2 fills completion + failure overlays asynchronously — best-effort,
        // never blocks the initial render (M10 / §How.6.1 p1).
        await performDailyBootstrap(
            setLoading: { state = .loading },
            fetchPhase1: { self.provider.dailyTrio(date: today) },
            onPhase1: { trio in
                // Phase 1: render immediately with overlays unknown (#530).
                state = .loaded(Self.mergeCards(trio: trio, completed: [], failed: []))
            },
            onPhase1Error: { _ in /* unreachable: dailyTrio is non-throwing */ },
            fetchPhase2: { trio in
                // Phase 2: fill completion + failure overlays — non-blocking, best-effort.
                await self.fillCompletionAndFailureOverlay(trio: trio, date: today)
            }
        )
    }

    /// Re-runs the phase-2 completion/failure-overlay fetch outside
    /// `bootstrap()`'s one-shot gate (#761), mirroring how
    /// `GameRootViewModel.refreshResumeCandidate()` bypasses `bootstrap()`'s own
    /// gate for the resume pill. Closing the Completion overlay after solving a
    /// daily returns to this same, un-destroyed hub instance — nothing
    /// re-triggered a load, so the just-solved card stayed unchecked until the
    /// whole hub was torn down and remounted.
    ///
    /// Called from `MinesweeperDailyHubView`'s `.onChange(of: sessionTeardownCount)`
    /// — `GameRoot`'s explicit game-session-teardown signal (#761). An earlier
    /// version of this fix rode `.onAppear`, on the theory that it re-fires
    /// whenever the hub becomes visible again; simulator verification disproved
    /// that for the real Close → Leave flow (a dismissing `fullScreenCover`
    /// does not re-fire the covered view's `.onAppear` at all — the only
    /// re-fire is a transient push-pop at board OPEN, which is useless here
    /// since completion doesn't exist yet). The same verification also found
    /// `refresh()` at first mount passes its guards on Minesweeper (MS board
    /// generation is synchronous, so `hasBootstrapped` and `.loaded` are both
    /// already true by the time `.onAppear` used to fire) — the `.loaded` guard
    /// below is a correctness guard, not a "no-op on first mount" claim.
    /// Mirrors `SudokuUI.DailyHubViewModel.refresh()`.
    ///
    /// Re-fetches only completed/failed ids, not the trio (today's boards never
    /// change) — cheap, like `refreshResumeCandidate`'s single query.
    public func refresh() async {
        guard hasBootstrapped, case .loaded(let cards) = state else { return }
        await fillCompletionAndFailureOverlay(trio: cards.map(\.entry), date: dateProvider())
    }

    /// Phase-2 overlay fill: fetches completed and failed daily ids, then
    /// re-merges them with the already-rendered cards. Called after `state` is
    /// already `.loaded`, so a hang or failure here cannot block the initial
    /// render. Errors are funneled through `errorReporter` (OSLog-observable)
    /// and degrade silently to "no cards marked" — same M10 contract as #526.
    /// Also the target of `refresh()`'s re-fetch (#761).
    /// #774: `completed` is now sourced from the rolling 7-day week-strip
    /// window (today's slot) instead of a standalone single-day fetch — the
    /// dispatch spec's "×7 total" fetch budget (not "×7 in addition to the
    /// existing 1") depends on this reuse. `failed` stays an independent,
    /// single-day fetch (unrelated to the strip/streak — see
    /// `MinesweeperDailyStrip`'s header comment on why a mine-hit loss never
    /// feeds the streak model at all).
    private func fillCompletionAndFailureOverlay(trio: [MinesweeperDailyEntry], date: Date) async {
        // #842: re-armed on every entry (bootstrap AND refresh) and cleared
        // via `defer` regardless of which return path fires below — mirrors
        // `SudokuUI.DailyHubViewModel.fillCompletionOverlay`'s gate exactly.
        isPhase2Pending = true
        defer { isPhase2Pending = false }
        guard case .loaded = state else { return }

        // #886/#912: the per-difficulty best-time read, the week-window
        // fetch, AND the failed-ids fetch all race concurrently
        // (`async let` — three independent CK read lanes, no ordering
        // dependency between any of them). #912 removed the prior
        // sequential `window` → `failed` shape (each `await`ed in turn,
        // stacking on top of `fetchWeekWindow`'s own now-concurrent 7-day
        // fan-out) — that leftover sequencing was the last serial hop in
        // MS's phase-2 lane. Production `PrivateCKGateway` conformers are
        // plain actors with per-call state, so concurrent calls just
        // serialize at the actor's mailbox — never deadlock; a round-1
        // attempt at the best-time fetch misread a single-continuation TEST
        // FAKE's limitation (`GatedQueryGateway`, since fixed to queue
        // multiple pending continuations) as a production concurrency
        // hazard and sequentialized needlessly.
        async let bestTimesTask = fetchBestTimes(trio: trio)
        async let windowTask = fetchWeekWindow(referenceDate: date)
        async let failedTask = fetchFailedIds(date: date)
        let window = await windowTask
        let failed = await failedTask
        let bestTimes = await bestTimesTask
        let completed: Set<String> = window?.first { $0.offsetFromToday == 0 }?.completedPuzzleIds ?? []

        guard case .loaded(let latestCards) = state else { return }
        if let window {
            let days = window.map { slot in
                MinesweeperDailyStripDay(
                    offsetFromToday: slot.offsetFromToday,
                    date: slot.date,
                    isCompleted: !slot.completedPuzzleIds.isEmpty,
                    completedPuzzleIds: slot.completedPuzzleIds
                )
            }
            let rawStreak = MinesweeperDailyStripLogic.computeStreak(days: days)
            weekStrip = MinesweeperDailyStripSnapshot(days: days, streak: rawStreak > 0 ? rawStreak : nil)
        } else {
            // #774: any single day's fetch failing (or no `savedGameStore`
            // injected at all — preview/test callsites) degrades the WHOLE
            // window rather than risk a false "missed" dot.
            weekStrip = .unknown
        }
        // #886: best times always merge in, independent of whether this
        // round's completed/failed sets carried any new information — an
        // independent read with no false-claim risk (a missing best time on
        // one difficulty while the others show real numbers isn't
        // misleading, just incomplete). `isCompleted`/`isFailed` are ONLY
        // recomputed when this round actually found something (preserving
        // the pre-#886 gate's exact semantics: no spurious "un-marks" a
        // prior success/failure just because this round's fetch came back
        // empty).
        let shouldRemergeCompletionState = !completed.isEmpty || !failed.isEmpty
        state = .loaded(latestCards.map { card in
            let isCompleted = shouldRemergeCompletionState ? completed.contains(card.id) : card.isCompleted
            let isFailed = shouldRemergeCompletionState ? (!isCompleted && failed.contains(card.id)) : card.isFailed
            return MinesweeperDailyCard(
                entry: card.entry,
                isCompleted: isCompleted,
                isFailed: isFailed,
                bestTimeSeconds: bestTimes[card.difficulty]
            )
        })
    }

    /// Route for a tapped daily card:
    /// - Completed (won): re-surfaces the result via `.completion` (#386).
    /// - Failed (hit a mine): pushes the `.board` for a free replay —
    ///   the replay is unscored/unsubmitted and does NOT overwrite the
    ///   Failed record (Epic 8 / SDD-003; the board VM guards this via
    ///   `isReplay`). The `.board` route carries `isReplay: true` so the
    ///   board knows not to persist or submit GC on this attempt.
    /// - Not-yet-played: pushes the `.board` normally (daily-mode, scored).
    public func cardTapped(_ card: MinesweeperDailyCard) {
        // #842: UX-responsiveness half of the defense-in-depth pair — see
        // `isPhase2Pending`'s doc. Correctness is
        // `MinesweeperDailyOpenGuardView`'s job even when this gate is
        // bypassed or races closed anyway.
        guard !isPhase2Pending else { return }
        if card.isCompleted {
            path.wrappedValue.append(.completion(difficulty: card.difficulty, mode: .daily))
        } else if card.isFailed {
            path.wrappedValue.append(
                .replayDailyBoard(difficulty: card.difficulty, seed: card.seed)
            )
        } else {
            path.wrappedValue.append(.board(difficulty: card.difficulty, seed: card.seed, mode: .daily))
        }
    }

    /// #826: tap entry point for a dot in the #774 week strip. Mirrors
    /// `SudokuUI.DailyHubViewModel.dayTapped` — only a REVIEWABLE (≥1
    /// parseable completed id, `MinesweeperDailyStripDay.isReviewable`),
    /// PAST day reacts. The view's tappable gate and this guard are built on
    /// the SAME `MinesweeperDailyStripLogic.reviewChoices` parse, so a dot
    /// can never render as a button whose tap would no-op here (CR round 2).
    /// Owner adjudication 2026-07-16: exactly one completed difficulty opens
    /// its Completion directly; more than one presents `reviewPickerChoices`.
    /// Unlike Sudoku, MS's `.completion` push needs no async fetch (no
    /// stored elapsed, #284) — fully synchronous, no in-flight latch needed.
    /// #882 F-5 (audit #874): deliberately NOT gated on `isPhase2Pending`,
    /// unlike `cardTapped`. Mirrors `SudokuUI.DailyHubViewModel.dayTapped`'s
    /// reasoning (not repeated in full here) — `weekStrip` stays `.unknown`
    /// (card hidden entirely) until phase 2 first resolves, and on a later
    /// `refresh()` re-entry it keeps showing the last successful, immutable
    /// snapshot (completion is monotonic, so staleness can only under-report,
    /// never mis-route). MS's `openReview` is even more immune than Sudoku's:
    /// it does no fetch at all — `.completion(difficulty:mode:day:)` is built
    /// purely from `choice.puzzleId`/`choice.difficulty`, both already frozen
    /// identifiers baked into the tapped `MinesweeperDailyStripDay` at render
    /// time, so there is no live-data re-read for a race to land in.
    /// Documented rather than gated per the #882 dispatch.
    public func dayTapped(_ day: MinesweeperDailyStripDay) {
        guard !day.isToday else { return }
        let choices = MinesweeperDailyStripLogic.reviewChoices(from: day.completedPuzzleIds)
        guard !choices.isEmpty else { return }
        if choices.count == 1 {
            openReview(choices[0])
        } else {
            reviewPickerChoices = choices
        }
    }

    /// The confirmationDialog picker's row selection (#826).
    public func reviewChoiceSelected(_ choice: MinesweeperDailyReviewChoice) {
        reviewPickerChoices = nil
        openReview(choice)
    }

    /// The confirmationDialog picker's Cancel / dismiss (#826).
    public func dismissReviewPicker() {
        reviewPickerChoices = nil
    }

    private func openReview(_ choice: MinesweeperDailyReviewChoice) {
        // `MinesweeperSavedGameStore.dailyDay(fromRecordName:)` reuses the
        // exact same day-parse #700's achievement streak already relies on
        // (puzzleId == recordName for daily records) rather than
        // re-deriving the day substring here.
        let day = MinesweeperSavedGameStore.dailyDay(fromRecordName: choice.puzzleId)
        path.wrappedValue.append(.completion(difficulty: choice.difficulty, mode: .daily, day: day))
    }

    /// Merge the daily trio with the sets of completed and failed daily ids into
    /// cards. A card is completed iff its `puzzleId` is in `completed`; failed
    /// iff in `failed` (and not also completed — a completed win takes priority).
    /// Pure + `nonisolated` so state-marking is unit-testable without standing
    /// up a persistence conformer.
    nonisolated static func mergeCards(
        trio: [MinesweeperDailyEntry],
        completed: Set<String>,
        failed: Set<String> = []
    ) -> [MinesweeperDailyCard] {
        trio.map { entry in
            let isCompleted = completed.contains(entry.puzzleId)
            let isFailed = !isCompleted && failed.contains(entry.puzzleId)
            return MinesweeperDailyCard(
                entry: entry,
                isCompleted: isCompleted,
                isFailed: isFailed
            )
        }
    }
}
