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

    struct WeekWindowSlot: Sendable {
        let offsetFromToday: Int
        let date: Date
        let completedPuzzleIds: Set<String>
    }

    /// #774: the rolling window size — also the streak display's cap (see
    /// the "7+" caption branch in `DailyStripView`). 7 matches the strip's own 7
    /// dots; changing this changes both simultaneously by construction.
    static let weekStripWindowSize = 7

    /// #912: fetches `fetchCompletedDailyIds(for:)` for all 7 days in the
    /// rolling window CONCURRENTLY (a task-group fan-out) rather than one
    /// sequential CK round-trip at a time — the 7-serial shape was the
    /// dominant contributor to the Daily hub's enable-latency window
    /// (`isPhase2Pending` stays true until this resolves). `persistence` is
    /// captured into a local `let` (not `self`) before the fan-out so the
    /// child closures don't need to cross the MainActor-isolated class
    /// boundary — `any PersistenceProtocol` is `Sendable`, and production
    /// `PrivateCKGateway`-backed conformers are plain actors, so concurrent
    /// calls into the SAME instance just serialize at the actor's mailbox
    /// (never deadlock — see `fillCompletionOverlay`'s doc on the identical
    /// reasoning for the `async let` window/best-time fan-out).
    ///
    /// Returns `nil` on the first failure — an all-or-nothing degrade, not a
    /// partial window, so a transient fetch failure on one day can never
    /// render as a false "missed" dot next to 6 real ones.
    /// `withThrowingTaskGroup` cancels every still-running child task before
    /// rethrowing, so a failing day never leaves orphaned work behind.
    ///
    /// Task-group completion order is NOT submission order, so the result is
    /// explicitly re-sorted oldest (`offsetFromToday: 6`) to newest
    /// (`offsetFromToday: 0` == today) before returning — callers (the week
    /// strip, `DailyStripView`) depend on that ordering, not just on which
    /// days are present.
    func fetchWeekWindow(referenceDate: Date) async -> [WeekWindowSlot]? {
        let persistence = self.persistence
        let offsets = stride(from: Self.weekStripWindowSize - 1, through: 0, by: -1)
        do {
            let slots = try await withThrowingTaskGroup(of: WeekWindowSlot.self) { group in
                for offset in offsets {
                    let dayDate = referenceDate.addingTimeInterval(-Double(offset) * 86_400)
                    group.addTask {
                        let completed = try await persistence.fetchCompletedDailyIds(for: dayDate)
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
                source: "DailyHubViewModel.fetchWeekWindow"
            )
            return nil
        }
    }
}
