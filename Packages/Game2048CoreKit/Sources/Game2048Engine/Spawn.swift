// Spawn — tile spawning logic for 2048.
//
// After each legal move, one new tile is placed at a uniformly-chosen empty
// cell. The tile value is 2 (probability 0.9) or 4 (probability 0.1).
//
// Randomness is exclusively via SplitMix64 from DeterminismKit.
// Same seed + identical move sequence ⇒ identical spawn sequence.
//
// Spawn algorithm (two draws per spawn from the RNG):
//   1. posIdx = rng.nextInt(upperBound: emptyCount) → index into emptyIndices
//   2. typeRoll = rng.nextInt(upperBound: 10) → value = (typeRoll < 9) ? 2 : 4

public import DeterminismKit

public enum Spawn {

    /// Spawn one tile onto `board` using `rng`. Returns the updated board and the
    /// spawned tile's (index, value). Precondition: board must have at least one
    /// empty cell.
    public static func spawnTile(
        onto board: Board,
        rng: inout some DeterministicRNG
    ) -> (board: Board, index: Int, value: Int) {
        let empty = board.emptyIndices
        precondition(!empty.isEmpty, "cannot spawn onto a full board")
        let posIdx = rng.nextInt(upperBound: empty.count)
        let cellIndex = empty[posIdx]
        let typeRoll = rng.nextInt(upperBound: 10)
        let value = typeRoll < 9 ? 2 : 4
        var updated = board
        updated.setTile(at: cellIndex, value: value)
        return (updated, cellIndex, value)
    }
}
