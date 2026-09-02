// DailyHubViewModel+Review — the past-day review flow (#826/#830): a
// completed PAST day's week-strip dot tap, its confirmationDialog picker, and
// the shared completed-daily-reopen fetch both routes (`cardTapped`'s
// completed branch AND this file's `openReview`) call through.
//
// Split out of the main class body purely to keep DailyHubViewModel.swift
// under the 400-line `file_length` lint ceiling (#1021 Phase B pushed it
// over) — this is not a separate concern from the main file, same rationale
// as `+BestTime.swift` / `+WeekWindow.swift`. `reviewPickerChoices` and
// `isOpeningCompleted` are `internal(set)` / `internal` on the main class
// specifically so this file can write them.

import Foundation
import SudokuEngine
import Telemetry

extension DailyHubViewModel {

    /// #826: tap entry point for a dot in the #774 week strip. Only a
    /// REVIEWABLE (≥1 parseable completed id — see
    /// `DailyStripDay.isReviewable`), PAST day reacts. The view's tappable
    /// gate (`DailyStripView.isTappable`) and this guard are built on the
    /// SAME `DailyStripLogic.reviewChoices` parse, so a dot can never render
    /// as a button whose tap would no-op here (CR round 2). Owner
    /// adjudication 2026-07-16: exactly one completed difficulty opens its
    /// Completion directly (reusing `openCompleted`'s async fetch path, same
    /// as `cardTapped`'s completed branch); more than one presents
    /// `reviewPickerChoices`, a confirmationDialog hosted by `DailyHubView`.
    /// #882 F-5 (audit #874): NOT gated on `isPhase2Pending`, unlike
    /// `cardTapped` (trusts a phase-1 placeholder, routes to `.board`
    /// unchecked — the race #842 closes). No equivalent risk: `weekStrip`
    /// stays `.unknown` until phase 2 first lands; `refresh()` keeps the
    /// last IMMUTABLE snapshot (completion is monotonic, staleness only
    /// under-reports); every completed open re-fetches fresh via
    /// `openCompleted`'s `loadIfExists` anyway. Documented, not gated.
    public func dayTapped(_ day: DailyStripDay) {
        guard !day.isToday else { return }
        let choices = DailyStripLogic.reviewChoices(from: day.completedPuzzleIds)
        guard !choices.isEmpty else { return }
        if choices.count == 1 {
            openReview(choices[0])
        } else {
            reviewPickerChoices = choices
        }
    }

    /// The confirmationDialog picker's row selection (#826).
    public func reviewChoiceSelected(_ choice: DailyReviewChoice) {
        reviewPickerChoices = nil
        openReview(choice)
    }

    /// The confirmationDialog picker's Cancel / dismiss (#826).
    public func dismissReviewPicker() {
        reviewPickerChoices = nil
    }

    private func openReview(_ choice: DailyReviewChoice) {
        // Same in-flight latch as `cardTapped`'s completed branch (#385) —
        // a picker row tap and a direct single-difficulty open both fan out
        // through the same async `openCompleted`.
        guard !isOpeningCompleted else { return }
        isOpeningCompleted = true
        Task { await openCompleted(puzzleId: choice.puzzleId, difficulty: choice.difficulty) }
    }

    /// Loads the completed daily's saved snapshot to recover its frozen
    /// `elapsedSeconds`, then routes to the Completion screen. On a load
    /// failure we report through the funnel and fall back to `.board` — never
    /// worse than the pre-#379 behavior, and never silently stuck.
    ///
    /// #830: uses `loadIfExists`, not `loadOrCreate` — the latter swallows a
    /// fetch failure into "treat as absent" and would synthesize a virgin
    /// `.completion(elapsedSeconds: 0, mistakeCount: 0)` for a
    /// legitimately-completed game whose record simply failed to fetch
    /// (transient CK error, cold cache). A `nil` result (confirmed absence —
    /// unexpected for a card the caller already believes is completed) is
    /// treated the same as a thrown fetch error: neither has real completion
    /// data to show, so both fall back to `.board`.
    ///
    /// #826: widened from `(_ card: DailyCard)` to `(puzzleId:difficulty:)` —
    /// the only two fields the body ever read — so a past-day tap
    /// (`dayTapped`/`openReview`, which has no `DailyCard`/`PuzzleEnvelope`
    /// for a day outside today's trio) can reuse this exact fetch path
    /// instead of duplicating it.
    func openCompleted(puzzleId: String, difficulty: Difficulty) async {
        // Reset on both success and the error/fallback path so a later tap
        // (#385) re-enters cleanly. `@MainActor` guarantees this runs without
        // an interleaved `cardTapped` between the route append and the clear.
        defer { isOpeningCompleted = false }
        do {
            guard let snapshot = try await persistence.loadIfExists(
                puzzleId: puzzleId,
                mode: .daily,
                difficulty: difficulty
            ) else {
                // Confirmed absence: no record to review. Never worse than a
                // fetch failure — fall back to `.board` the same way.
                path.append(.board(puzzleId: puzzleId))
                return
            }
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
