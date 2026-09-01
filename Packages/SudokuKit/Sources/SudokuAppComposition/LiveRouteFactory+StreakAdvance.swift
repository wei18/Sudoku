// LiveRouteFactory+StreakAdvance — #1023 Phase B streak-ritual (M3/M4)
// resolution. Extracted to a sibling file (repo convention: `+Feature.swift`
// rather than growing the host file past SwiftLint's 400-line `file_length`
// ceiling — `LiveRouteFactory.swift` was already near that ceiling before
// this addition) — same route table's `.board` case, not a separate concern.
// Mirrors Minesweeper's `LiveRouteFactory+DailyBoardOpen.makeFetchStreakAdvance`.

import Foundation
internal import GameShellUI
internal import Persistence
internal import SudokuUI
internal import SudokuEngine

extension LiveRouteFactory {

    // MARK: - Streak ritual resolution (#1023 Phase B)

    /// The window size, mirrored from `DailyHubViewModel.weekStripWindowSize`
    /// (`internal` to `SudokuUI`, not visible here) — same duplicated-constant
    /// shape #774 already accepts between the Hub VM and its own `+WeekWindow`
    /// extension; a 3rd copy here is consistent with that precedent, not a
    /// new one.
    private static let weekStripWindowSize = 7

    /// Pre/post streak state for the M3/M4 ritual (design.md §6). Reuses the
    /// SAME `DailyStripLogic.computeStreak(days:)` the Daily hub's week strip
    /// uses — no second streak algorithm. `currentPuzzleId` is explicitly
    /// excluded from today's "pre" set and unioned into "post" so the result
    /// is correct regardless of whether the just-finished solve's async
    /// persist has landed in `fetchCompletedDailyIdsByDay()` yet (see impl
    /// notes for the race this avoids). Returns `nil` on fetch failure — no
    /// streak section renders, matching `fetchWeekWindow`'s own
    /// all-or-nothing degrade.
    @MainActor
    static func makeFetchStreakAdvance(
        currentPuzzleId: String,
        persistence: any PersistenceProtocol
    ) -> @MainActor () async -> CompletionStreakAdvance? {
        {
            guard let completedByDay = try? await persistence.fetchCompletedDailyIdsByDay() else { return nil }
            let today = Date()
            let offsets = stride(from: weekStripWindowSize - 1, through: 0, by: -1)
            var preDays: [DailyStripDay] = []
            var postDays: [DailyStripDay] = []
            for offset in offsets {
                let dayDate = today.addingTimeInterval(-Double(offset) * 86_400)
                let dayKey = UTCDay.string(from: dayDate)
                var ids = completedByDay[dayKey] ?? []
                if offset == 0 {
                    ids.remove(currentPuzzleId)
                    preDays.append(DailyStripDay(offsetFromToday: offset, date: dayDate, isCompleted: !ids.isEmpty))
                    ids.insert(currentPuzzleId)
                    postDays.append(DailyStripDay(offsetFromToday: offset, date: dayDate, isCompleted: true))
                } else {
                    let day = DailyStripDay(offsetFromToday: offset, date: dayDate, isCompleted: !ids.isEmpty)
                    preDays.append(day)
                    postDays.append(day)
                }
            }
            return CompletionStreakAdvance(
                pipStates: postDays.map(\.isCompleted),
                preCount: DailyStripLogic.computeStreak(days: preDays),
                postCount: DailyStripLogic.computeStreak(days: postDays)
            )
        }
    }
}
