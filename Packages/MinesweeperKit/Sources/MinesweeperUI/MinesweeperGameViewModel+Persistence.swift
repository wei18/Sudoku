// MinesweeperGameViewModel+Persistence — saved-game store writes (#455 step 4).
//
// Split into its own file (not the main class body) purely to keep
// MinesweeperGameViewModel.swift under the 400-line `file_length` lint
// ceiling — this is the same file-split rationale as
// `+SubmitOnWin.swift` / `+EvaluateAchievements.swift` (`store`,
// `recordName`, `isSeeded`, `errorReporter` are `internal`, not `private`,
// specifically so this file can see them).

public import MinesweeperPersistence
public import Telemetry

extension MinesweeperGameViewModel {

    // MARK: - Persistence (#455 step 4)

    /// Persist the current board through the saved-game store. Trigger points:
    /// pause, terminal reveal (`reveal()`, in the main class body), and the
    /// view-lifecycle hooks (`scenePhase == .background`, `onDisappear`) in
    /// `MinesweeperBoardView`. No-ops when the persistence seam isn't threaded
    /// (MVP/preview/tests), when seeded (#297 fixtures must stay
    /// side-effect-free), or while the board is still `.idle` (a
    /// zero-information pre-first-reveal save would occupy the resume pill
    /// for nothing). Failures funnel — a failed save never interrupts
    /// gameplay (mirrors Sudoku's flush; conflict policy is the documented
    /// MVP bare-throw → funnel, #463 CR).
    public func persistCurrentState() async {
        guard !isSeeded, let store, let recordName else { return }
        guard snapshot.status != .idle else { return }
        do {
            try await store.save(snapshot, modeRaw: mode.rawValue, recordName: recordName)
        } catch {
            await errorReporter?.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "MinesweeperGameViewModel.persistCurrentState"
            )
        }
    }

    // MARK: - Pause / resume (#434)
    //
    // Live here (not the main class body) because `pause()` is itself a
    // persist trigger point — and the move keeps MinesweeperGameViewModel.swift
    // under the 400-line lint ceiling after the #823 terminal-chain rework.

    /// Pause the game: freeze the elapsed clock + flip to `.paused`. No-op when
    /// seeded (preview/snapshot) or when the actor isn't `.playing` (the actor
    /// itself guards the transition). Mirrors Sudoku's `GameViewModel.pause()`.
    public func pause() async {
        guard !isSeeded else { return }
        snapshot = await session.pause()
        // #455: a pause is a natural save point (mirrors Sudoku's
        // pause-triggered flush, §How.5.5).
        await persistCurrentState()
    }

    /// Resume the game: restart the clock + flip back to `.playing`. No-op when
    /// seeded or when the actor isn't `.paused`. Mirrors Sudoku's
    /// `GameViewModel.resume()`.
    public func resume() async {
        guard !isSeeded else { return }
        snapshot = await session.resume()
    }
}
