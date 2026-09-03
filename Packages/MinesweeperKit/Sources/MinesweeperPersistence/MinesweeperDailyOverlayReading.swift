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
//
// #1021 Phase B (Leader-approved additive widening): `latestInProgress()`
// added so `MinesweeperDailyHubViewModel`'s Today in-progress card can read
// it — `MinesweeperSavedGameStore` already implements this exact method (for
// the resume pill seam), so this is pure exposure, not a new capability;
// every existing conformer (`UITestSeededCompletedDailyOverlayReading`)
// updated alongside.

public import Foundation

public protocol MinesweeperDailyOverlayReading: Sendable {
    func fetchFailedDailyIds(for date: Date) async throws -> Set<String>
    func fetchCompletedDailyIdsByDay() async throws -> [String: Set<String>]
    func latestInProgress() async throws -> MinesweeperSavedGameSummary?
}

extension MinesweeperSavedGameStore: MinesweeperDailyOverlayReading {}
