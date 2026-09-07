// MinesweeperDailyHubViewModel+Review — the past-day review flow (#826):
// a completed PAST day's week-strip dot tap + its confirmationDialog picker.
// Mirrors `SudokuUI.DailyHubViewModel+Review.swift`.
//
// Split out of the main class body purely to keep
// MinesweeperDailyHubViewModel.swift under the 400-line `file_length` lint
// ceiling (#1021 Phase B pushed it over) — same rationale as `+Overlay.swift`.
// `reviewPickerChoices` and `path` are `internal`(-set) on the main class
// specifically so this file can write/read them.

import MinesweeperPersistence

extension MinesweeperDailyHubViewModel {

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
}
