// MinesweeperSessionSnapshot — Sendable value summarizing a session for UI.
//
// `MinesweeperSession` (actor) produces a fresh snapshot after every
// mutation; the ViewModel binds to this and SwiftUI diffs the cell array.
//
// Pure value type — no Apple-framework imports beyond Foundation (for Date,
// which is intentionally NOT included in MVP — we expose `elapsedSeconds:
// Int`, not a wall clock).

public import MinesweeperEngine

public struct MinesweeperSessionSnapshot: Sendable, Equatable, Hashable, Codable {
    public let difficulty: Difficulty
    /// Seed the owning `MinesweeperEngine` was built from. Persisted so a
    /// restored session reconstructs the identical seed-derived board (#455).
    public let seed: UInt64
    public let cells: [Cell]
    public let status: MinesweeperSessionStatus
    public let elapsedSeconds: Int
    public let mineCount: Int
    public let flagCount: Int
    /// Whether a flag was PLACED at any point in this game's history, even if
    /// later removed (`flagCount` only reflects the current board). Backs the
    /// "No Flags Needed" achievement (#700) across save/resume — a fresh
    /// ViewModel over a restored session must not forget an earlier flag.
    /// Back-compat: blobs written before #700 lack this key and decode as
    /// `false`; `MinesweeperSession.applySnapshot` additionally ORs in
    /// `flagCount > 0` as a conservative fallback for such legacy saves
    /// (accepted historical exemption — MS saves are TestFlight-internal,
    /// same precedent as the `wireStatus` migration note).
    public let everFlagged: Bool

    public var rows: Int { difficulty.rows }
    public var columns: Int { difficulty.columns }

    /// Board indices where `cells[i].isMine`, regardless of reveal state
    /// (#841). `cells` always carries the full mine layout — even for
    /// hidden cells — so any snapshot (in-progress, won, or lost) captured
    /// after mine placement can hand its layout to
    /// `MinesweeperSession.init(difficulty:seed:fixedMineIndices:)` to
    /// replay the identical board. Feeds the daily-retry loader, which
    /// reads this off a "failed" record `loadInProgress` deliberately
    /// excludes.
    public var mineIndices: Set<Int> {
        Set(cells.indices.filter { cells[$0].isMine })
    }

    public init(
        difficulty: Difficulty,
        seed: UInt64 = 0,
        cells: [Cell],
        status: MinesweeperSessionStatus,
        elapsedSeconds: Int,
        mineCount: Int,
        flagCount: Int,
        everFlagged: Bool = false
    ) {
        self.difficulty = difficulty
        self.seed = seed
        self.cells = cells
        self.status = status
        self.elapsedSeconds = elapsedSeconds
        self.mineCount = mineCount
        self.flagCount = flagCount
        self.everFlagged = everFlagged
    }

    /// Custom decode only to give `everFlagged` a missing-key default —
    /// pre-#700 blobs don't carry it. Encoding stays synthesized.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.difficulty = try container.decode(Difficulty.self, forKey: .difficulty)
        self.seed = try container.decode(UInt64.self, forKey: .seed)
        self.cells = try container.decode([Cell].self, forKey: .cells)
        self.status = try container.decode(MinesweeperSessionStatus.self, forKey: .status)
        self.elapsedSeconds = try container.decode(Int.self, forKey: .elapsedSeconds)
        self.mineCount = try container.decode(Int.self, forKey: .mineCount)
        self.flagCount = try container.decode(Int.self, forKey: .flagCount)
        self.everFlagged = try container.decodeIfPresent(Bool.self, forKey: .everFlagged) ?? false
    }

    public func cell(row: Int, col: Int) -> Cell {
        cells[row * difficulty.columns + col]
    }
}
