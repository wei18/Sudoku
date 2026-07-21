// DailyHubViewModel+WeekWindow — #774 rolling 7-day completed-ids fetch.
//
// Split out of the main class body purely to keep DailyHubViewModel.swift
// under the 400-line `file_length` lint ceiling (#886 pushed it over) — this
// extension is not a separate concern, it's the same phase-2 overlay-fill
// logic `fillCompletionOverlay` (in the main file) calls, same rationale as
// `MinesweeperGameViewModel+SubmitOnWin.swift`. `WeekWindowSlot` is
// `internal` (not `private`) so `fillCompletionOverlay`'s inferred usage of
// `fetchWeekWindow`'s return type resolves across the file boundary;
// `persistence` / `errorReporter` are `internal` on the main class for the
// same cross-file-access reason.

import Foundation
import SudokuEngine
import Telemetry

extension DailyHubViewModel {

    struct WeekWindowSlot: Sendable {
        let offsetFromToday: Int
        let date: Date
        let completedPuzzleIds: Set<String>
    }

    /// #774: the rolling window size — also the streak display's cap (see
    /// the "7+" caption branch in `DailyStripView`). 7 matches the strip's own 7
    /// dots; changing this changes both simultaneously by construction.
    static let weekStripWindowSize = 7

    /// #921: fetches `persistence.fetchCompletedDailyIdsByDay()` ONCE and
    /// slices the 7 window slots out of that single day-bucketed result,
    /// rather than #912's concurrent 7-way task-group fan-out. That fan-out
    /// fixed the LATENCY of the original sequential loop, but each of the 7
    /// calls hit `fetchCompletedDailyIds(for:)`'s own per-day CK query — 7
    /// round-trips to fetch data one query can return in full (mirrors
    /// `MinesweeperSavedGameStore.fetchCompletedDailyIdsByDay`, #915).
    ///
    /// Returns `nil` on failure — an all-or-nothing degrade, not a partial
    /// window, so a transient fetch failure can never render as a false
    /// "missed" dot next to 6 real ones.
    ///
    /// Slots are built directly in oldest (`offsetFromToday: 6`) to newest
    /// (`offsetFromToday: 0` == today) order — the `stride` map is already in
    /// that order, so (unlike the old task-group fan-out, whose completion
    /// order was NOT submission order) no explicit re-sort is needed. Callers
    /// (the week strip, `DailyStripView`) depend on this ordering.
    func fetchWeekWindow(referenceDate: Date) async -> [WeekWindowSlot]? {
        let offsets = stride(from: Self.weekStripWindowSize - 1, through: 0, by: -1)
        do {
            let completedByDay = try await persistence.fetchCompletedDailyIdsByDay()
            return offsets.map { offset in
                let dayDate = referenceDate.addingTimeInterval(-Double(offset) * 86_400)
                let dayKey = UTCDay.string(from: dayDate)
                return WeekWindowSlot(
                    offsetFromToday: offset,
                    date: dayDate,
                    completedPuzzleIds: completedByDay[dayKey] ?? []
                )
            }
        } catch {
            await errorReporter.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "DailyHubViewModel.fetchWeekWindow"
            )
            return nil
        }
    }
}
