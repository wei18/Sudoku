// MinesweeperGameViewModel — @MainActor @Observable bridge between the
// `MinesweeperSession` actor and SwiftUI's `MinesweeperBoardView`.
//
// Pattern mirrors Sudoku's GameViewModel: the actor is the source of truth;
// the ViewModel caches the most recent snapshot and republishes it to the
// view tree after every `await` round-trip.
//
// MVP scope: no telemetry, no undo, no persistence (per dispatch spec).

public import MinesweeperEngine
public import MinesweeperGameState
public import Observation

@MainActor
@Observable
public final class MinesweeperGameViewModel {

    // MARK: - Session

    public let session: MinesweeperSession

    // MARK: - Cached snapshot

    public private(set) var snapshot: MinesweeperSessionSnapshot

    // MARK: - Convenience accessors (read-only projections of snapshot)

    public var rows: Int { snapshot.rows }
    public var columns: Int { snapshot.columns }
    public var cells: [Cell] { snapshot.cells }
    public var status: MinesweeperSessionStatus { snapshot.status }
    public var mineCount: Int { snapshot.mineCount }
    public var flagCount: Int { snapshot.flagCount }
    public var elapsedSeconds: Int { snapshot.elapsedSeconds }
    public var remainingMineCount: Int { max(0, mineCount - flagCount) }

    public var isTerminal: Bool { status == .won || status == .lost }

    // MARK: - Init

    /// Construct a fresh session from a difficulty + seed. Use this for
    /// most cases; the underlying actor is created internally.
    public convenience init(difficulty: Difficulty = .beginner, seed: UInt64 = 0) {
        self.init(session: MinesweeperSession(difficulty: difficulty, seed: seed))
    }

    /// Construct from an existing session. The view model derives its
    /// `difficulty` from `session.difficulty` so the two cannot disagree.
    public init(session: MinesweeperSession) {
        self.session = session
        let difficulty = session.difficulty
        // Synchronous bootstrap: snapshot before any action is just the
        // immutable initial state — we mirror it locally so SwiftUI has
        // something to render before the first action.
        self.snapshot = MinesweeperSessionSnapshot(
            difficulty: difficulty,
            cells: Array(repeating: Cell(), count: difficulty.cellCount),
            status: .idle,
            elapsedSeconds: 0,
            mineCount: difficulty.mineCount,
            flagCount: 0
        )
    }

    // MARK: - Refresh

    /// Pull the latest snapshot from the actor (e.g. for elapsed-time ticks).
    public func refresh() async {
        snapshot = await session.snapshot()
    }

    // MARK: - Actions

    public func cell(row: Int, col: Int) -> Cell {
        snapshot.cell(row: row, col: col)
    }

    public func reveal(row: Int, col: Int) async {
        do {
            snapshot = try await session.reveal(row: row, col: col)
        } catch {
            // MVP: out-of-bounds shouldn't happen from a well-formed grid view.
            // Swallow — the ViewModel state stays consistent with the last
            // successful snapshot.
        }
    }

    public func toggleFlag(row: Int, col: Int) async {
        do {
            snapshot = try await session.toggleFlag(row: row, col: col)
        } catch {
            // See `reveal`.
        }
    }
}
