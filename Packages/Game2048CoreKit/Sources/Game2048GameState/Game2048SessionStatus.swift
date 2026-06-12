// Game2048SessionStatus — lifecycle states for a 2048 session.
//
// Legal transitions:
//   .playing → .paused   (user pauses)
//   .paused  → .playing  (user resumes)
//   .playing → .stuck    (no legal move in any direction)
//
// 2048 has no forced win-terminal: reaching the 2048 tile sets
// `reachedTarget` on the snapshot but play continues. Stuck = no legal
// move in any direction (analogous to lost in Minesweeper).
// Mirrors MinesweeperSessionStatus's shape exactly.

public enum Game2048SessionStatus: String, Sendable, Hashable, Codable, CaseIterable {
    case playing
    case paused
    case stuck
}
