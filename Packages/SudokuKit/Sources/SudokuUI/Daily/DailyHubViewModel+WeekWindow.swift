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
import Telemetry

extension DailyHubViewModel {

    struct WeekWindowSlot {
        let offsetFromToday: Int
        let date: Date
        let completedPuzzleIds: Set<String>
    }

    /// #774: the rolling window size — also the streak display's cap (see
    /// the "7+" caption branch in `DailyStripView`). 7 matches the strip's own 7
    /// dots; changing this changes both simultaneously by construction.
    static let weekStripWindowSize = 7

    /// Fetches `fetchCompletedDailyIds(for:)` once per day in the rolling
    /// window, oldest (`offsetFromToday: 6`) to newest (`offsetFromToday: 0`
    /// == today). Returns `nil` on the first failure — an all-or-nothing
    /// degrade, not a partial window, so a transient fetch failure on one day
    /// can never render as a false "missed" dot next to 6 real ones.
    func fetchWeekWindow(referenceDate: Date) async -> [WeekWindowSlot]? {
        var slots: [WeekWindowSlot] = []
        slots.reserveCapacity(Self.weekStripWindowSize)
        for offset in stride(from: Self.weekStripWindowSize - 1, through: 0, by: -1) {
            let dayDate = referenceDate.addingTimeInterval(-Double(offset) * 86_400)
            do {
                let completed = try await persistence.fetchCompletedDailyIds(for: dayDate)
                slots.append(WeekWindowSlot(offsetFromToday: offset, date: dayDate, completedPuzzleIds: completed))
            } catch {
                await errorReporter.report(
                    UserFacingError.classify(error),
                    underlying: error,
                    source: "DailyHubViewModel.fetchWeekWindow"
                )
                return nil
            }
        }
        return slots
    }
}
