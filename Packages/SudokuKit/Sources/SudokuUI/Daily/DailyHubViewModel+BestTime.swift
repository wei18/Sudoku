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
    func fetchBestTimes(trio: [PuzzleEnvelope]) async -> [Difficulty: Int] {
        var bestTimes: [Difficulty: Int] = [:]
        for envelope in trio {
            let difficulty = envelope.identity.difficulty
            do {
                let record = try await persistence.fetchPersonalRecord(mode: .daily, difficulty: difficulty)
                if let best = record.bestTimeSeconds {
                    bestTimes[difficulty] = best
                }
            } catch {
                await errorReporter.report(
                    UserFacingError.classify(error),
                    underlying: error,
                    source: "DailyHubViewModel.fetchBestTimes"
                )
            }
        }
        return bestTimes
    }
}
