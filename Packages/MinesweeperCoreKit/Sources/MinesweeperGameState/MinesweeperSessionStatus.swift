// MinesweeperSessionStatus — minimal MVP lifecycle for a Minesweeper session.
//
// Legal transitions:
//   .idle    → .playing  (first reveal or first flag toggle)
//   .playing → .paused   (user pauses; #434)
//   .paused  → .playing  (user resumes; #434)
//   .playing → .won      (all non-mine cells revealed)
//   .playing → .lost     (a mine cell is revealed)
//
// Terminal states (.won / .lost) freeze the elapsed-time clock. Pause (#434)
// also freezes the clock while paused, mirroring Sudoku's GameSession.

public enum MinesweeperSessionStatus: String, Sendable, Hashable, Codable, CaseIterable {
    case idle
    case playing
    case paused
    case won
    case lost
}
