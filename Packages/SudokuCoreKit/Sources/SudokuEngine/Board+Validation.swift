// Board validation — row / column / box duplicate detection + solved predicate.
//
// All operations are pure value-based: no Foundation, no Set ordering relied upon
// in iteration (we iterate fixed-range arrays, per docs/v1/design.md §How.4.6).

extension Board {

    /// Returns 0-based box index for (row, col) — boxes laid out left-to-right,
    /// top-to-bottom, each 3×3. Box(0) covers rows 0..2, cols 0..2.
    public static func boxIndex(row: Int, column: Int) -> Int {
        (row / 3) * 3 + (column / 3)
    }

    /// Collects all duplicate-digit conflicts present in the current board.
    /// A cell with digit 0 (empty) does not participate.
    /// Returns conflicts in a deterministic order (row units, then column units, then box units;
    /// within each unit, by digit ascending).
    public func conflicts() -> [Conflict] {
        var result: [Conflict] = []
        // Row scan.
        for row in 0..<Self.dimension {
            var seen = [UInt8](repeating: 0, count: 10) // index 1..9
            for col in 0..<Self.dimension {
                let value = cells[Self.index(row: row, column: col)]
                if value == 0 { continue }
                seen[Int(value)] &+= 1
            }
            for digit in 1...9 where seen[digit] > 1 {
                result.append(.row(row, digit: digit))
            }
        }
        // Column scan.
        for col in 0..<Self.dimension {
            var seen = [UInt8](repeating: 0, count: 10)
            for row in 0..<Self.dimension {
                let value = cells[Self.index(row: row, column: col)]
                if value == 0 { continue }
                seen[Int(value)] &+= 1
            }
            for digit in 1...9 where seen[digit] > 1 {
                result.append(.column(col, digit: digit))
            }
        }
        // Box scan.
        for box in 0..<Self.dimension {
            var seen = [UInt8](repeating: 0, count: 10)
            let rowBase = (box / 3) * 3
            let colBase = (box % 3) * 3
            for deltaRow in 0..<3 {
                for deltaCol in 0..<3 {
                    let value = cells[Self.index(row: rowBase + deltaRow, column: colBase + deltaCol)]
                    if value == 0 { continue }
                    seen[Int(value)] &+= 1
                }
            }
            for digit in 1...9 where seen[digit] > 1 {
                result.append(.box(box, digit: digit))
            }
        }
        return result
    }

    /// A board is solved iff every cell is filled (1–9) and there are zero conflicts.
    public var isSolved: Bool {
        isFullyFilled && conflicts().isEmpty
    }
}
