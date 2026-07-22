// DailyHubViewModel+BestTime — #886 per-difficulty best-DAILY-time fetch.
//
// Split into its own file purely to keep DailyHubViewModel.swift under the
// 400-line `file_length` lint ceiling — this extension is not a separate
// concern, it's the same phase-2 overlay-fill logic as
// `fillCompletionOverlay`, which calls it (same rationale as
// `MinesweeperGameViewModel+SubmitOnWin.swift`). `persistence` /
// `errorReporter` are `internal` on the main class specifically so this file
// can read them.

import Foundation
import SudokuEngine
import SudokuPersistence
import Telemetry

extension DailyHubViewModel {

    /// #886: per-difficulty best DAILY time (`fetchPersonalRecord(mode: .daily, difficulty:)`
    /// — the existing Stats-screen seam, zero new Persistence surface). Mirrors
    /// `StatsViewModel.fetchTiles`'s per-tile independent try/catch, NOT
    /// `fetchWeekWindow`'s all-or-nothing degrade: a fetch failure on one
    /// difficulty degrades only that difficulty's entry to "no value" (renders
    /// as "—" via `StatsTileView.timeLabel(nil)`), the other two still show
    /// real numbers. Absence of a key (as opposed to an explicit `nil`) covers
    /// both "fetch failed" and "record has no best time yet" — same collapse
    /// `StatsTile.empty` already applies, so the hub draws no distinction the
    /// Stats screen itself doesn't bother with.
    ///
    /// #941: the 3 per-difficulty fetches used to run in a serial `for` loop —
    /// the last remaining serial CK round-trip in the phase-2 lane (the
    /// week-window fetch and this whole method already race concurrently via
    /// `fillCompletionOverlay`'s `async let`). Fanned out into a `TaskGroup`
    /// here so all `trio.count` reads are in flight simultaneously; `persistence`
    /// / `errorReporter` are captured as local `let`s (both `Sendable`
    /// existentials) rather than `self` so the child tasks don't need to hop
    /// through the `@MainActor`-isolated view model. Assembly is
    /// order-independent — results are collected into a `[Difficulty: Int]`
    /// keyed off each task's own difficulty, never off completion order.
    func fetchBestTimes(trio: [PuzzleEnvelope]) async -> [Difficulty: Int] {
        let persistence = self.persistence
        let errorReporter = self.errorReporter
        return await withTaskGroup(of: (Difficulty, Int?).self) { group in
            for envelope in trio {
                let difficulty = envelope.identity.difficulty
                group.addTask {
                    do {
                        let record = try await persistence.fetchPersonalRecord(mode: .daily, difficulty: difficulty)
                        return (difficulty, record.bestTimeSeconds)
                    } catch {
                        await errorReporter.report(
                            UserFacingError.classify(error),
                            underlying: error,
                            source: "DailyHubViewModel.fetchBestTimes"
                        )
                        return (difficulty, nil)
                    }
                }
            }
            var bestTimes: [Difficulty: Int] = [:]
            for await (difficulty, best) in group {
                if let best {
                    bestTimes[difficulty] = best
                }
            }
            return bestTimes
        }
    }
}
