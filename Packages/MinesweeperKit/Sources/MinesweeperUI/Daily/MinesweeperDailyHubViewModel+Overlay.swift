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

    struct WeekWindowSlot: Sendable {
        let offsetFromToday: Int
        let date: Date
        let completedPuzzleIds: Set<String>
    }

    /// #774: the rolling window size — also the streak display's cap (see
    /// the "7+" caption branch in `MinesweeperDailyStripView`).
    static let weekStripWindowSize = 7

    /// #912: fetches `savedGameStore.fetchCompletedDailyIds(for:)` for all 7
    /// days in the rolling window CONCURRENTLY (a task-group fan-out) rather
    /// than one sequential CK round-trip at a time — mirrors
    /// `SudokuUI.DailyHubViewModel.fetchWeekWindow`'s identical fix. MS's
    /// pre-fix shape was worse than Sudoku's: this loop ran sequentially
    /// AND `fillCompletionAndFailureOverlay` then awaited `fetchFailedIds`
    /// sequentially too (see that method) — 8 total serial round-trips.
    /// `savedGameStore` is captured into a local `let` before the fan-out so
    /// the child closures don't need to cross the MainActor-isolated class
    /// boundary — `MinesweeperSavedGameStore` is an `actor` (implicitly
    /// `Sendable`), so concurrent calls into the SAME instance just
    /// serialize at the actor's mailbox (never deadlock).
    ///
    /// Returns `nil` when `savedGameStore` is absent, or on the first fetch
    /// failure — an all-or-nothing degrade, not a partial window.
    /// `withThrowingTaskGroup` cancels every still-running child task before
    /// rethrowing, so a failing day never leaves orphaned work behind.
    ///
    /// Task-group completion order is NOT submission order, so the result is
    /// explicitly re-sorted oldest (`offsetFromToday: 6`) to newest
    /// (`offsetFromToday: 0` == today) before returning — callers (the week
    /// strip, `MinesweeperDailyStripView`) depend on that ordering.
    func fetchWeekWindow(referenceDate: Date) async -> [WeekWindowSlot]? {
        guard let savedGameStore else { return nil }
        let offsets = stride(from: Self.weekStripWindowSize - 1, through: 0, by: -1)
        do {
            let slots = try await withThrowingTaskGroup(of: WeekWindowSlot.self) { group in
                for offset in offsets {
                    let dayDate = referenceDate.addingTimeInterval(-Double(offset) * 86_400)
                    group.addTask {
                        let completed = try await savedGameStore.fetchCompletedDailyIds(for: dayDate)
                        return WeekWindowSlot(offsetFromToday: offset, date: dayDate, completedPuzzleIds: completed)
                    }
                }
                var collected: [WeekWindowSlot] = []
                collected.reserveCapacity(Self.weekStripWindowSize)
                for try await slot in group {
                    collected.append(slot)
                }
                return collected
            }
            return slots.sorted { $0.offsetFromToday > $1.offsetFromToday }
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
