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

    struct WeekWindowSlot {
        let offsetFromToday: Int
        let date: Date
        let completedPuzzleIds: Set<String>
    }

    /// #774: the rolling window size — also the streak display's cap (see
    /// the "7+" caption branch in `MinesweeperDailyStripView`).
    static let weekStripWindowSize = 7

    /// Fetches `savedGameStore.fetchCompletedDailyIds(for:)` once per day in
    /// the rolling window, oldest (`offsetFromToday: 6`) to newest
    /// (`offsetFromToday: 0` == today). Returns `nil` when `savedGameStore`
    /// is absent, or on the first fetch failure — an all-or-nothing degrade.
    func fetchWeekWindow(referenceDate: Date) async -> [WeekWindowSlot]? {
        guard let savedGameStore else { return nil }
        var slots: [WeekWindowSlot] = []
        slots.reserveCapacity(Self.weekStripWindowSize)
        for offset in stride(from: Self.weekStripWindowSize - 1, through: 0, by: -1) {
            let dayDate = referenceDate.addingTimeInterval(-Double(offset) * 86_400)
            do {
                let completed = try await savedGameStore.fetchCompletedDailyIds(for: dayDate)
                slots.append(WeekWindowSlot(offsetFromToday: offset, date: dayDate, completedPuzzleIds: completed))
            } catch {
                await errorReporter.report(
                    UserFacingError.classify(error),
                    underlying: error,
                    source: "MinesweeperDailyHubViewModel.fetchWeekWindow"
                )
                return nil
            }
        }
        return slots
    }
}
