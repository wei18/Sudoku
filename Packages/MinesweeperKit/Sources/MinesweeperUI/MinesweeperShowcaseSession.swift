// MinesweeperShowcaseSession — DEBUG-only fixed showcase board (#1054).
//
// Produces a deterministic, byte-stable mid-game board for the App Store
// 03-board marketing capture: a revealed region (flood-filled from a fixed
// first click) plus 3 flags planted on real mines.
//
// Deliberate shape deviation from the sibling `MinesweeperNearWinSession`:
// that builder restores a `MinesweeperSession` ACTOR (`.restore(from:)`,
// always normalized to `.paused`) so the player's one remaining tap can win
// the game. This builder instead mounts via
// `MinesweeperGameViewModel(seeded:)` — the #297 snapshot/preview seam — for
// two reasons specific to a marketing capture:
//   1. `.paused` mounts `PauseOverlayView`, a full-screen mask that hides the
//      board entirely (`MinesweeperBoardView.swift`) — the opposite of what a
//      store screenshot needs.
//   2. A LIVE `.playing` session's `elapsedSeconds` advances off a real
//      `MonotonicClock`; two captures taken seconds apart would show
//      different times and fail the required byte-identical hash check
//      (#1054 acceptance item 6). `(seeded:)` sets `isSeeded = true`, which
//      makes `MinesweeperBoardView`'s `.task { refresh() }` ticker a no-op —
//      the cached snapshot (and its `elapsedSeconds`) never changes, no
//      matter how long the board stays on screen.
//
// Accepted asymmetry vs. `SudokuShowcaseBoard` (CR round 2, PM ruling): Sudoku's
// builder goes through the LIVE `GameSession` actor with an injected frozen
// clock instead. `MinesweeperSession.restore(from:clock:)` does expose a
// `clock:` parameter, but `applySnapshot` unconditionally normalizes a
// restored `.playing` to `.paused`, and the only way back to a genuinely
// `.playing` state is an async `resume()` call on the actor.
// `MinesweeperFreshBoardLoaderView.makeViewModel(...)` — the seam this
// builder is injected into — is a synchronous function (`.task(id:) { state =
// .loaded(makeViewModel()) }`), so wiring in that async restore+resume dance
// would mean restructuring the loader's synchronous seam. Sudoku's
// `BoardLoaderView.mountLoaded` is already `async` (it awaits
// `GameSession.restore` + `viewModel.startOrResume()`), so the same
// frozen-clock + resume approach is cheap there instead — see that file's
// header doc for the full reasoning.
//
// Availability: `#if DEBUG` only — stripped from Release builds entirely.

#if DEBUG

internal import MinesweeperEngine
public import MinesweeperGameState

/// A fixed, deterministic mid-game Minesweeper board. See the header doc
/// above for why this is a plain snapshot builder, not a session restore.
public enum MinesweeperShowcaseSession {

    /// Fixed seed for the showcase board. Distinct from
    /// `MinesweeperAppComposition.uitestBoardSeed` (`0x5EED_B1`, a FRESH
    /// board for the `board:<difficulty>` key) and
    /// `MinesweeperNearWinSession.nearWinSeed` (`0xAABB_CCDD_EEFF_0011`).
    /// #1054 CR round 2 (PM ruling): chosen, together with
    /// `firstClickRow`/`firstClickCol` below, by a brute-force search over
    /// nearby seeds × first-click cells for a combination whose flood-reveal
    /// opens a region with at least 3 mines FORCED by the basic
    /// single-constraint count rule (see `flagsQualifyingAsForced(engine:)`)
    /// — this exact seed + cell yields 7 such forced mines (comfortably over
    /// the 3 flagged) with a 20-cell revealed region.
    /// `MinesweeperShowcaseSessionTests` pins the result.
    public static let seed: UInt64 = 0xC0FF_EE15_5C0B_0008

    /// First-click cell — bottom-center of the beginner grid. Fixed
    /// alongside `seed` (see its doc): the combination is what produces the
    /// 20-cell revealed region / 7 forced mines.
    private static let firstClickRow = 8
    private static let firstClickCol = 4

    /// Frozen elapsed-time value baked into the snapshot. Never advances —
    /// see the header doc's determinism rationale.
    private static let elapsedSeconds = 42

    /// Number of real mines flagged in the fixed scenario.
    private static let flaggedMineCount = 3

    /// The fixed showcase snapshot. A `static let` initializer runs lazily,
    /// exactly once per process, on first access — so every caller
    /// (the loader, tests) observes the identical value.
    public static let snapshot: MinesweeperSessionSnapshot = {
        let difficulty = Difficulty.beginner
        var engine = MinesweeperEngine(difficulty: difficulty, seed: seed)
        // First-click-safe placement, then a real flood-reveal of the
        // connected zero region from `firstClickRow`/`firstClickCol` — never
        // hand-set state.
        _ = try? engine.reveal(row: firstClickRow, col: firstClickCol)

        // Flag up to `flaggedMineCount` real, still-hidden mines via the
        // engine's own `toggleFlag` — never by hand-writing `Cell.state`.
        // #1054 CR round 2 (PM ruling, strengthens round 1's adjacency-only
        // check): a flag must be FORCED by the basic single-constraint count
        // rule — there must exist a revealed neighbor cell whose displayed
        // number equals ITS OWN count of non-revealed (hidden or flagged)
        // neighbors, which makes every one of that revealed cell's
        // non-revealed neighbors (this candidate included) a certain mine.
        // Mere adjacency to a revealed cell is not enough (a "2" with 3
        // non-revealed neighbors doesn't pin any single one of them).
        // Row-major among the qualifying set for determinism; if fewer than
        // `flaggedMineCount` qualify, only those are flagged — never falls
        // back to an unforced mine.
        var flaggedCount = 0
        for index in engine.cells.indices where flaggedCount < flaggedMineCount {
            let cell = engine.cells[index]
            guard cell.isMine, cell.state == .hidden else { continue }
            guard hasForcingWitness(atIndex: index, engine: engine) else { continue }
            let row = index / engine.columns
            let col = index % engine.columns
            _ = try? engine.toggleFlag(row: row, col: col)
            flaggedCount += 1
        }

        return MinesweeperSessionSnapshot(
            difficulty: difficulty,
            seed: seed,
            cells: engine.cells,
            status: .playing,
            elapsedSeconds: elapsedSeconds,
            mineCount: engine.mineCount,
            flagCount: flaggedCount,
            everFlagged: flaggedCount > 0
        )
    }()

    /// True iff some revealed neighbor of `index` "forces" it as a mine by
    /// the basic single-constraint count rule: that neighbor's displayed
    /// `neighborMineCount` equals its OWN count of non-revealed (hidden or
    /// flagged) neighboring cells — meaning every one of those non-revealed
    /// neighbors, `index` included, must be a mine. `internal` (not
    /// `private`) so `MinesweeperShowcaseSessionTests` can independently
    /// recompute the witness for each flag from the built board, rather than
    /// hard-coding coordinates.
    static func hasForcingWitness(atIndex index: Int, engine: MinesweeperEngine) -> Bool {
        forcingWitness(atIndex: index, engine: engine) != nil
    }

    /// The board index of a revealed cell that forces `index` as a mine (see
    /// `hasForcingWitness`), or `nil` if none exists.
    static func forcingWitness(atIndex index: Int, engine: MinesweeperEngine) -> Int? {
        let row = index / engine.columns
        let col = index % engine.columns
        for neighborIndex in engine.neighborIndices(row: row, col: col) {
            let neighbor = engine.cells[neighborIndex]
            guard neighbor.state == .revealed else { continue }
            let neighborRow = neighborIndex / engine.columns
            let neighborCol = neighborIndex % engine.columns
            let nonRevealedCount = engine.neighborIndices(row: neighborRow, col: neighborCol)
                .filter { engine.cells[$0].state != .revealed }
                .count
            if neighbor.neighborMineCount == nonRevealedCount {
                return neighborIndex
            }
        }
        return nil
    }
}

#endif
