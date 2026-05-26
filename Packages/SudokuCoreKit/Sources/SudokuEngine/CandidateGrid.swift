// CandidateGrid — bitmask candidate sets for an in-progress Board.
//
// Internal helper used by Solver / UniquenessValidator / Calibrator.
// Each cell holds a UInt16 mask where bit (digit - 1) is set if `digit`
// is still a legal candidate for that cell.

struct CandidateGrid {
    /// `masks[index]` for an *empty* cell holds the set of currently legal digits.
    /// For a *filled* cell it holds 0 (irrelevant — read cells[index] instead).
    var masks: [UInt16]

    static let allDigits: UInt16 = 0b0000_0001_1111_1111 // bits 0..8 = digits 1..9

    /// Build candidate masks from a board's current cells.
    /// Pure function of board state — does not consider conflicts; assumes the
    /// board is partially-consistent (no duplicates in any unit).
    init(board: Board) {
        var masks = [UInt16](repeating: 0, count: Board.cellCount)
        for index in 0..<Board.cellCount where board.cellRaw(at: index) == 0 {
            var used: UInt16 = 0
            for cellIdx in CandidateGrid.peers(of: index) {
                let value = board.cellRaw(at: cellIdx)
                if value != 0 {
                    used |= 1 << (value - 1)
                }
            }
            masks[index] = CandidateGrid.allDigits & ~used
        }
        self.masks = masks
    }

    // MARK: - Unit + peer index tables (precomputed at first access)

    static let rowsIndices: [[Int]] = (0..<Board.dimension).map { row in
        (0..<Board.dimension).map { Board.index(row: row, column: $0) }
    }
    static let colsIndices: [[Int]] = (0..<Board.dimension).map { col in
        (0..<Board.dimension).map { Board.index(row: $0, column: col) }
    }
    static let boxesIndices: [[Int]] = (0..<Board.dimension).map { box in
        let rowBase = (box / 3) * 3
        let colBase = (box % 3) * 3
        var indices: [Int] = []
        indices.reserveCapacity(9)
        for deltaRow in 0..<3 {
            for deltaCol in 0..<3 {
                indices.append(Board.index(row: rowBase + deltaRow, column: colBase + deltaCol))
            }
        }
        return indices
    }

    static let unitsForCell: [[[Int]]] = {
        var table: [[[Int]]] = Array(repeating: [], count: Board.cellCount)
        for index in 0..<Board.cellCount {
            let row = index / Board.dimension
            let col = index % Board.dimension
            let box = Board.boxIndex(row: row, column: col)
            table[index] = [rowsIndices[row], colsIndices[col], boxesIndices[box]]
        }
        return table
    }()

    static let peersTable: [[Int]] = {
        var table: [[Int]] = Array(repeating: [], count: Board.cellCount)
        for index in 0..<Board.cellCount {
            var set = Set<Int>()
            for unit in unitsForCell[index] {
                for cellIdx in unit where cellIdx != index {
                    set.insert(cellIdx)
                }
            }
            table[index] = set.sorted() // deterministic order
        }
        return table
    }()

    static func peers(of index: Int) -> [Int] { peersTable[index] }
    static func units(of index: Int) -> [[Int]] { unitsForCell[index] }

    // MARK: - Bitmask helpers

    static func popcount(_ mask: UInt16) -> Int {
        mask.nonzeroBitCount
    }

    /// If exactly one bit is set, returns the corresponding digit (1...9). Otherwise nil.
    static func lonelyDigit(_ mask: UInt16) -> Int? {
        guard popcount(mask) == 1 else { return nil }
        return mask.trailingZeroBitCount + 1
    }

    /// Iterate digits (1..9) currently set in `mask`.
    static func digits(in mask: UInt16) -> [Int] {
        var result: [Int] = []
        for digit in 1...9 where mask & (1 << (digit - 1)) != 0 {
            result.append(digit)
        }
        return result
    }
}
