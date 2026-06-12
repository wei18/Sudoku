// Game2048SessionSnapshot — Sendable value summarising a session for UI binding.
//
// `Game2048Session` (actor) produces a fresh snapshot after every mutation;
// the ViewModel binds to this and SwiftUI diffs the tile array.
// Pure value type — no Apple-framework imports beyond those already in
// Game2048Engine. Mirrors MinesweeperSessionSnapshot exactly.

public import Game2048Engine

public struct Game2048SessionSnapshot: Sendable, Equatable, Hashable, Codable {
    /// Seed the session was built from (persisted for resume round-trip).
    public let seed: UInt64
    public let board: Board
    public let score: Int
    public let moveCount: Int
    public let status: Game2048SessionStatus
    public let elapsedSeconds: Int
    /// True if the board contains at least one tile with value ≥ 2048.
    /// Set once and stays true for the rest of the session (play continues).
    public let reachedTarget: Bool

    /// Explicit keys: these names are load-bearing for persistence round-trips
    /// (CloudKit blob in Milestone 4) — renames must be deliberate (CR #490 F4).
    private enum CodingKeys: String, CodingKey {
        case seed, board, score, moveCount, status, elapsedSeconds, reachedTarget
    }

    public init(
        seed: UInt64,
        board: Board,
        score: Int,
        moveCount: Int,
        status: Game2048SessionStatus,
        elapsedSeconds: Int,
        reachedTarget: Bool
    ) {
        self.seed = seed
        self.board = board
        self.score = score
        self.moveCount = moveCount
        self.status = status
        self.elapsedSeconds = elapsedSeconds
        self.reachedTarget = reachedTarget
    }
}
