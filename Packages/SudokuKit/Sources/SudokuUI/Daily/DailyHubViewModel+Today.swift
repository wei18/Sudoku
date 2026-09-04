// DailyHubViewModel+Today — #1021 Phase B: `TodayMapper`'s data seams — the
// best-effort in-progress summary fetch, the all-time completed-day
// derivation, and the phase-2 degrade signal. Split out purely to keep
// DailyHubViewModel.swift under the 400-line `file_length` lint ceiling
// (same rationale as `+BestTime.swift` / `+WeekWindow.swift`).

import Foundation
import GameShellUI
import Persistence
import Telemetry

extension DailyHubViewModel {

    /// Fetches `latestInProgress()` for the Today hub's in-progress card
    /// status text/thumbnail. Best-effort — absence (`nil`) or a thrown
    /// fetch both degrade to "no in-progress card", never to `.degraded`
    /// (unlike the week-window fetch): not knowing about an in-progress save
    /// is not the same as not knowing completion status.
    func fetchInProgressSummary() async -> SavedGameSummary? {
        do {
            return try await persistence.latestInProgress()
        } catch {
            await errorReporter.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "DailyHubViewModel.fetchInProgressSummary"
            )
            return nil
        }
    }

    /// Derives the all-time completed-day set from the SAME day-bucketed
    /// dictionary `fetchWeekWindow` already fetched (`WeekWindowResult`) —
    /// not a second read.
    static func completedDays(from completedByDay: [String: Set<String>]) -> Set<DayKey> {
        Set(completedByDay.keys.compactMap(DayKey.key))
    }

    /// `true` once phase-2's week-window fetch has resolved
    /// (`!isPhase2Pending`) and come back empty-handed
    /// (`weekStrip.days.isEmpty`) — the all-or-nothing degrade
    /// `fillCompletionOverlay` applies. Distinct from "hasn't run yet" (still
    /// `isPhase2Pending`, `weekStrip` at its initial `.unknown`): only the
    /// SETTLED-but-empty combination means the fetch genuinely failed.
    /// `TodayMapper` reads this to force every card to "not started"
    /// (design.md §3.1 `degraded` row) without a second CK read.
    var isPhase2Degraded: Bool {
        !isPhase2Pending && weekStrip.days.isEmpty
    }
}
