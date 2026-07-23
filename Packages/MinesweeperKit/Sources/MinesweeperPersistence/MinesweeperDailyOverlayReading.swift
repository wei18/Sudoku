// MinesweeperDailyOverlayReading — #935 batch 3, the narrow read-only seam
// `MinesweeperDailyHubViewModel`'s phase-2 overlay fetch actually needs off
// `MinesweeperSavedGameStore` (a concrete actor with no protocol seam prior
// to this).
//
// Verified call sites (`MinesweeperDailyHubViewModel+Overlay.swift`): the VM
// calls exactly `fetchFailedDailyIds(for:)` and `fetchCompletedDailyIdsByDay()`
// on its `savedGameStore` — nothing else. Extracting a protocol over just
// those two lets a DEBUG-only fake stand in for the live store (so the N13
// re-view completion route can be seeded deterministically — see
// `MinesweeperAppComposition.UITestSeededCompletedDailyOverlayReading`)
// without widening every OTHER `MinesweeperSavedGameStore` consumer (board
// save/resume/replay in `LiveRouteFactory`, `MinesweeperDailyOpenGuardView`'s
// `fetchCompletedDailyIds(for:)` today-only re-check) to a protocol they
// don't need.

public import Foundation

public protocol MinesweeperDailyOverlayReading: Sendable {
    func fetchFailedDailyIds(for date: Date) async throws -> Set<String>
    func fetchCompletedDailyIdsByDay() async throws -> [String: Set<String>]
}

extension MinesweeperSavedGameStore: MinesweeperDailyOverlayReading {}
