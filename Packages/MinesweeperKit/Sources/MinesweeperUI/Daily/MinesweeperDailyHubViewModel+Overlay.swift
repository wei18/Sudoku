// MinesweeperDailyHubViewModel+Overlay — phase-2 overlay fetches: failed-ids,
// #886 per-difficulty best-DAILY-time, and #774 rolling 7-day completed-ids
// window.
//
// Split out of the main class body purely to keep
// MinesweeperDailyHubViewModel.swift under the 400-line `file_length` lint
// ceiling (#886 pushed it over) — these are not a separate concern, they're
// the same phase-2 overlay-fill logic `fillCompletionAndFailureOverlay` (in
// the main file) calls, same rationale as
// `MinesweeperGameViewModel+SubmitOnWin.swift`. `WeekWindowSlot` is
// `internal` (not `private`) so `fillCompletionAndFailureOverlay`'s inferred
// usage of `fetchWeekWindow`'s return type resolves across the file
// boundary; `savedGameStore` / `personalRecordStore` / `errorReporter` are
// `internal` on the main class for the same cross-file-access reason.

import Foundation
import MinesweeperEngine
import MinesweeperGameState
import Telemetry

extension MinesweeperDailyHubViewModel {

    /// #886: extracted from the inline do/catch purely for readability
    /// (`fillCompletionAndFailureOverlay` calls this alongside the
    /// week-window and best-time fetches). Behavior unchanged: a `nil` store
    /// or a thrown fetch both degrade to an empty set (reported through the
    /// funnel on throw).
    func fetchFailedIds(date: Date) async -> Set<String> {
        guard let savedGameStore else { return [] }
        do {
            return try await savedGameStore.fetchFailedDailyIds(for: date)
        } catch {
            await errorReporter.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "MinesweeperDailyHubViewModel.fetchFailedDailyIds"
            )
            return []
        }
    }

    /// #886: per-difficulty best DAILY time (`fetch(modeRaw: "daily", difficulty:)`
    /// — the existing Stats-screen seam, zero new Persistence surface). Mirrors
    /// `MinesweeperStatsViewModel.fetchTiles`'s per-tile independent try/catch,
    /// NOT `fetchWeekWindow`'s all-or-nothing degrade: a fetch failure on one
    /// difficulty degrades only that difficulty's entry to "no value" (renders
    /// as "—" via `MinesweeperStatsTileView.timeLabel(nil)`), the other two
    /// still show real numbers. Absence of a key (as opposed to an explicit
    /// `nil`) covers both "fetch failed" and "record has no best time yet" —
    /// same collapse `MinesweeperStatsTile.empty` already applies.
    func fetchBestTimes(trio: [MinesweeperDailyEntry]) async -> [Difficulty: Int] {
        guard let personalRecordStore else { return [:] }
        var bestTimes: [Difficulty: Int] = [:]
        for entry in trio {
            let difficulty = entry.difficulty
            do {
                let record = try await personalRecordStore.fetch(modeRaw: GameMode.daily.rawValue, difficulty: difficulty)
                if let best = record.bestTimeSeconds {
                    bestTimes[difficulty] = best
                }
            } catch {
                await errorReporter.report(
                    UserFacingError.classify(error),
                    underlying: error,
                    source: "MinesweeperDailyHubViewModel.fetchBestTimes"
                )
            }
        }
        return bestTimes
    }

    struct WeekWindowSlot: Sendable {
        let offsetFromToday: Int
        let date: Date
        let completedPuzzleIds: Set<String>
    }

    /// #774: the rolling window size — also the streak display's cap (see
    /// the "7+" caption branch in `MinesweeperDailyStripView`).
    static let weekStripWindowSize = 7

    /// #915: fetches `savedGameStore.fetchCompletedDailyIdsByDay()` ONCE and
    /// slices the 7 window slots out of that single day-bucketed result,
    /// rather than #912's concurrent 7-way task-group fan-out. That fan-out
    /// fixed the LATENCY of the naive sequential loop, but each of the 7
    /// calls hit `fetchCompletedDailyIds(for:)`'s date-agnostic CK query
    /// (`status == "completed"`, filtered to one day client-side) — 7
    /// BYTE-IDENTICAL CloudKit reads differing only in which day's result
    /// they kept. One query now covers the whole window.
    ///
    /// Returns `nil` when `savedGameStore` is absent, or on fetch failure —
    /// an all-or-nothing degrade, not a partial window.
    ///
    /// Slots are built directly in oldest (`offsetFromToday: 6`) to newest
    /// (`offsetFromToday: 0` == today) order — callers (the week strip,
    /// `MinesweeperDailyStripView`) depend on that ordering.
    func fetchWeekWindow(referenceDate: Date) async -> [WeekWindowSlot]? {
        guard let savedGameStore else { return nil }
        let offsets = stride(from: Self.weekStripWindowSize - 1, through: 0, by: -1)
        do {
            let completedByDay = try await savedGameStore.fetchCompletedDailyIdsByDay()
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
                source: "MinesweeperDailyHubViewModel.fetchWeekWindow"
            )
            return nil
        }
    }
}
