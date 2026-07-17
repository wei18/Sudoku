// swiftlint:disable identifier_name
// Short loop variables (`r`/`c`/`i`/`nr`/`nc`/`dr`/`dc`) are idiomatic
// for inner-loop grid traversal in this engine. Disabled at file scope.

// MARK: - MinesweeperEngine
//
// Pure-Swift Minesweeper game logic. Mirrors the shape of `SudokuEngine` in
// the sibling `SudokuCoreKit` package: value types, deterministic seeded RNG,
// `internal import Foundation`, no Apple-framework imports.
//
// Mine placement is **deferred until first reveal** (standard "first-click
// safe" convention): mines are placed lazily so that the first-clicked cell
// + its eight neighbors are guaranteed mine-free. Once placed, the board is
// fully determined by (difficulty, seed, firstClick).
//
// Flood-fill on a 0-count reveal cascades through connected zero cells and
// their numeric borders. Flagged cells are never auto-revealed by the
// cascade — players retain explicit control of their flags.

internal import Foundation

public struct MinesweeperEngine: Sendable {
    public let difficulty: Difficulty
    public let seed: UInt64
    public private(set) var cells: [Cell]
    public private(set) var moves: [Move]
    public private(set) var minesPlaced: Bool
    public private(set) var isLost: Bool

    public var rows: Int { difficulty.rows }
    public var columns: Int { difficulty.columns }
    public var mineCount: Int { difficulty.mineCount }

    public init(difficulty: Difficulty, seed: UInt64) {
        self.difficulty = difficulty
        self.seed = seed
        self.cells = Array(repeating: Cell(), count: difficulty.cellCount)
        self.moves = []
        self.minesPlaced = false
        self.isLost = false
    }

    /// Restore an engine to a previously-captured board state (persistence
    /// round-trip, #455). Does NOT touch the deterministic generation path —
    /// the supplied `cells` already encode the seed-derived mine layout +
    /// reveal/flag state. `moves` is reset (the undo/replay history is not
    /// persisted in MVP); win/lose is recomputed by the session from `status`.
    public init(
        difficulty: Difficulty,
        seed: UInt64,
        cells: [Cell],
        minesPlaced: Bool,
        isLost: Bool
    ) {
        self.difficulty = difficulty
        self.seed = seed
        self.cells = cells
        self.moves = []
        self.minesPlaced = minesPlaced
        self.isLost = isLost
    }

    /// Construct an engine with mines already placed at fixed board indices
    /// (#841 — daily-retry-must-be-one-fixed-game). Skips the deferred,
    /// first-click-salted placement path entirely: `minesPlaced` is `true`
    /// the moment this initializer returns, so `reveal()`'s
    /// `if !minesPlaced { placeMines(firstClickRow:col:) }` branch never
    /// fires and the layout can never be re-derived from THIS session's
    /// click. Used to replay a daily board with the canonical layout
    /// captured on the day's first-ever attempt — every retry (any first
    /// click) reproduces the identical board.
    ///
    /// No first-click safety: the fixed layout may already have a mine
    /// under the very first tap. That is the intended, documented contract
    /// for a fixed board (first-click safety only ever applied to the
    /// first-ever attempt, which is what produced this layout) — a mine hit
    /// here is a normal loss, not special-cased.
    ///
    /// Throws `.invalidFixedLayout` if `fixedMineIndices` doesn't contain
    /// exactly `difficulty.mineCount` in-bounds indices (a corrupt or
    /// legacy persisted layout) — callers should treat that as "no usable
    /// layout" and fall back to fresh (deferred, first-click-safe)
    /// placement rather than silently playing a malformed board.
    public init(difficulty: Difficulty, seed: UInt64, fixedMineIndices: Set<Int>) throws {
        self.difficulty = difficulty
        self.seed = seed
        self.cells = Array(repeating: Cell(), count: difficulty.cellCount)
        self.moves = []
        self.minesPlaced = false
        self.isLost = false
        try placeMines(atFixedIndices: fixedMineIndices)
    }

    // MARK: - Indexing

    public func index(row: Int, col: Int) -> Int { row * columns + col }

    public func inBounds(row: Int, col: Int) -> Bool {
        row >= 0 && row < rows && col >= 0 && col < columns
    }

    public func cell(at row: Int, col: Int) throws -> Cell {
        guard inBounds(row: row, col: col) else {
            throw MinesweeperError.outOfBounds(row: row, col: col)
        }
        return cells[index(row: row, col: col)]
    }

    // MARK: - Win / lose

    public var isWon: Bool {
        guard minesPlaced, !isLost else { return false }
        for cell in cells {
            if !cell.isMine && cell.state != .revealed { return false }
        }
        return true
    }

    // MARK: - Operations

    @discardableResult
    public mutating func reveal(row: Int, col: Int) throws -> [(row: Int, col: Int)] {
        guard inBounds(row: row, col: col) else {
            throw MinesweeperError.outOfBounds(row: row, col: col)
        }
        if isLost || isWon { return [] }

        let idx = index(row: row, col: col)
        switch cells[idx].state {
        case .flagged, .revealed: return []
        case .hidden: break
        }

        if !minesPlaced {
            try placeMines(firstClickRow: row, firstClickCol: col)
        }

        moves.append(.reveal(row: row, col: col))

        if cells[idx].isMine {
            cells[idx].state = .revealed
            isLost = true
            return [(row, col)]
        }

        return floodReveal(fromRow: row, col: col)
    }

    @discardableResult
    public mutating func toggleFlag(row: Int, col: Int) throws -> CellState {
        guard inBounds(row: row, col: col) else {
            throw MinesweeperError.outOfBounds(row: row, col: col)
        }
        if isLost || isWon { return cells[index(row: row, col: col)].state }

        let idx = index(row: row, col: col)
        switch cells[idx].state {
        case .revealed:
            return .revealed
        case .hidden:
            cells[idx].state = .flagged
            moves.append(.flag(row: row, col: col))
            return .flagged
        case .flagged:
            cells[idx].state = .hidden
            moves.append(.unflag(row: row, col: col))
            return .hidden
        }
    }

    // MARK: - Mine placement (deferred)

    private mutating func placeMines(firstClickRow: Int, firstClickCol: Int) throws {
        let firstIdx = index(row: firstClickRow, col: firstClickCol)
        var safeIndices = Set(neighborIndices(row: firstClickRow, col: firstClickCol))
        safeIndices.insert(firstIdx)

        let capacity = cells.count - safeIndices.count
        guard mineCount <= capacity else {
            throw MinesweeperError.tooManyMines(requested: mineCount, capacity: capacity)
        }

        var candidates: [Int] = []
        candidates.reserveCapacity(cells.count - safeIndices.count)
        for i in 0..<cells.count where !safeIndices.contains(i) {
            candidates.append(i)
        }

        // Mix first-click into seed so two different first-clicks on the same
        // base seed yield distinct layouts (which they must, since both must
        // avoid different safe regions).
        let firstClickSalt = UInt64(bitPattern: Int64(firstClickRow &* 73_856_093 &+ firstClickCol &* 19_349_663))
        var rng = SplitMix64(seed: seed &+ firstClickSalt)

        // Partial Fisher–Yates: select `mineCount` distinct indices.
        for i in 0..<mineCount {
            let j = i + rng.nextInt(upperBound: candidates.count - i)
            candidates.swapAt(i, j)
        }
        finalizePlacement(mineIndices: candidates[0..<mineCount])
    }

    /// #841: place mines at an externally-supplied, already-computed set of
    /// board indices — no RNG, no first-click safe zone. The caller (a
    /// daily-replay loader) is responsible for having captured a valid
    /// layout from the day's first-ever attempt; this just applies it.
    private mutating func placeMines(atFixedIndices indices: Set<Int>) throws {
        guard indices.count == mineCount, indices.allSatisfy({ (0..<cells.count).contains($0) }) else {
            throw MinesweeperError.invalidFixedLayout(expected: mineCount, found: indices.count)
        }
        finalizePlacement(mineIndices: indices)
    }

    /// Shared tail of both placement paths: flip `isMine` for every index in
    /// `mineIndices`, compute `neighborMineCount` for every non-mine cell,
    /// and flip `minesPlaced`. Pulled out of `placeMines(firstClickRow:col:)`
    /// verbatim (#841) — same statements, same order, so the frozen
    /// determinism vectors that path feeds are untouched.
    private mutating func finalizePlacement(mineIndices: some Sequence<Int>) {
        for i in mineIndices {
            cells[i].isMine = true
        }

        // Compute neighbor counts for every non-mine cell.
        for r in 0..<rows {
            for c in 0..<columns {
                let i = index(row: r, col: c)
                if cells[i].isMine { continue }
                var count = 0
                for n in neighborIndices(row: r, col: c) where cells[n].isMine {
                    count += 1
                }
                cells[i].neighborMineCount = count
            }
        }

        minesPlaced = true
    }

    // MARK: - Flood reveal

    private mutating func floodReveal(fromRow row: Int, col: Int) -> [(row: Int, col: Int)] {
        var revealed: [(row: Int, col: Int)] = []
        var stack: [(Int, Int)] = [(row, col)]
        while let (r, c) = stack.popLast() {
            let i = index(row: r, col: c)
            let cell = cells[i]
            if cell.state != .hidden { continue }
            if cell.isMine { continue }
            cells[i].state = .revealed
            revealed.append((r, c))
            if cell.neighborMineCount == 0 {
                for (nr, nc) in neighborCoords(row: r, col: c) {
                    let ni = index(row: nr, col: nc)
                    if cells[ni].state == .hidden && !cells[ni].isMine {
                        stack.append((nr, nc))
                    }
                }
            }
        }
        return revealed
    }

    // MARK: - Neighbor helpers

    public func neighborCoords(row: Int, col: Int) -> [(row: Int, col: Int)] {
        var out: [(Int, Int)] = []
        for dr in -1...1 {
            for dc in -1...1 where !(dr == 0 && dc == 0) {
                let nr = row + dr
                let nc = col + dc
                if inBounds(row: nr, col: nc) { out.append((nr, nc)) }
            }
        }
        return out
    }

    public func neighborIndices(row: Int, col: Int) -> [Int] {
        neighborCoords(row: row, col: col).map { index(row: $0.row, col: $0.col) }
    }
}

// swiftlint:enable identifier_name
