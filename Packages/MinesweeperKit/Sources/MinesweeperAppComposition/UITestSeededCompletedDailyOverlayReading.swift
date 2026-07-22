// UITestSeededCompletedDailyOverlayReading — #935 batch 3, DEBUG-only fault
// injection for `MinesweeperDailyOverlayReading`, gated by
// `-uitest-seed-completed-daily` (`GameAppKit.UITestLaunchArg.seedCompletedDaily`).
// Wraps the live `MinesweeperSavedGameStore` and reports today's daily trio
// (all three difficulties) as already completed, so the N13 re-view
// completion route (docs/navigation-flows.md) can be exercised
// deterministically — completed-daily state lives in CloudKit Private DB and
// cannot be produced by real play on a signed-out/offline CI simulator.
// Unlike Sudoku's counterpart, `MinesweeperDailyHubViewModel.cardTapped`
// pushes `.completion` synchronously off `card.isCompleted` alone — no
// snapshot fetch — so this fake only needs to make the completed-ids read
// report today's trio; `fetchFailedDailyIds` delegates to the wrapped store
// unchanged. Absent from Release builds via the `#if DEBUG` guard.

internal import Foundation
internal import MinesweeperEngine
// `UTCDay` lives in TimeKit; `MinesweeperGameState` re-exports it
// (`MonotonicClockReexport.swift`) — same transitive path
// `MinesweeperSavedGameStore` itself relies on.
internal import MinesweeperGameState
internal import MinesweeperPersistence
#if DEBUG
internal import GameAppKit
#endif

#if DEBUG

/// Wraps a live `MinesweeperDailyOverlayReading` (normally the concrete
/// `MinesweeperSavedGameStore`) and reports today's three daily record names
/// as completed. `fetchFailedDailyIds` delegates unchanged.
struct UITestSeededCompletedDailyOverlayReading: MinesweeperDailyOverlayReading {
    private let wrapped: (any MinesweeperDailyOverlayReading)?
    private let dateProvider: @Sendable () -> Date

    init(
        wrapping wrapped: (any MinesweeperDailyOverlayReading)?,
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.wrapped = wrapped
        self.dateProvider = dateProvider
    }

    func fetchFailedDailyIds(for date: Date) async throws -> Set<String> {
        (try? await wrapped?.fetchFailedDailyIds(for: date)) ?? []
    }

    /// Reports today's three daily record names as completed, unioned with
    /// whatever the wrapped live store genuinely has (best-effort — a
    /// signed-out/offline live store throwing here degrades to "nothing
    /// extra", never blocks the seeded ids).
    func fetchCompletedDailyIdsByDay() async throws -> [String: Set<String>] {
        var byDay = (try? await wrapped?.fetchCompletedDailyIdsByDay()) ?? [:]
        let today = dateProvider()
        let key = UTCDay.string(from: today)
        byDay[key, default: []].formUnion(Self.todaysDailyRecordNames(date: today))
        return byDay
    }

    /// Today's three daily record names — `MinesweeperDaily.puzzleId`'s
    /// format (`"daily-<YYYY-MM-DD>-<difficulty>"`), deterministic from the
    /// UTC day + difficulty.
    private static func todaysDailyRecordNames(date: Date) -> Set<String> {
        Set(MinesweeperDaily.dailyDifficulties.map {
            MinesweeperDaily.puzzleId(date: date, difficulty: $0)
        })
    }
}

#endif

/// Resolves the `MinesweeperDailyOverlayReading` seam consumed by
/// `MinesweeperDailyHubViewModel`. Under `-uitest-seed-completed-daily`
/// (DEBUG only), wraps `live` in `UITestSeededCompletedDailyOverlayReading`
/// so the N13 re-view completion route is reachable without CloudKit. Always
/// defined (mirrors `SudokuAppComposition.resolvePersistence`) so `Live.swift`
/// can call it unconditionally without its own `#if DEBUG`.
func resolveDailyOverlayReading(
    live: (any MinesweeperDailyOverlayReading)?
) -> (any MinesweeperDailyOverlayReading)? {
    #if DEBUG
    guard ProcessInfo.processInfo.arguments.contains(UITestLaunchArg.seedCompletedDaily) else {
        return live
    }
    return UITestSeededCompletedDailyOverlayReading(wrapping: live)
    #else
    return live
    #endif
}
