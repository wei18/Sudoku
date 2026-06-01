// MinesweeperSessionStatus — minimal MVP lifecycle for a Minesweeper session.
//
// Legal transitions:
//   .idle    → .playing  (first reveal or first flag toggle)
//   .playing → .won      (all non-mine cells revealed)
//   .playing → .lost     (a mine cell is revealed)
//
// Terminal states (.won / .lost) freeze the elapsed-time clock.
//
// MVP does NOT model pause/abandon — those are additive in a follow-up.

public enum MinesweeperSessionStatus: String, Sendable, Hashable, Codable, CaseIterable {
    case idle
    case playing
    case won
    case lost
}
