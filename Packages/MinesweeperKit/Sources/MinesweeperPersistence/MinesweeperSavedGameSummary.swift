// MinesweeperSavedGameSummary — projection of a Minesweeper `SavedGame`
// CloudKit record used at the store surface (`latestInProgress()`).
//
// MS-native by design (#455 / #460): the shared resume seam consumes a
// game-agnostic `ResumeCandidate<Route>` built from this summary by MS's own
// `fetchResume` closure, so this type deliberately does NOT reuse the
// Sudoku-typed `Persistence.SavedGameSummary` (whose `mode` / `difficulty`
// are SudokuEngine enums — `beginner/intermediate/expert` is unrepresentable
// there).
//
// `modeRaw` stays a raw `String` ("daily" / "practice") so this target does
// not import MinesweeperUI, where the `GameMode` enum lives — the composition
// root maps `GameMode ↔ String` at the seam (mirrors how Sudoku's store wires
// `mode.rawValue` onto the CK record).

public import Foundation
public import MinesweeperEngine

/// Wire values for the `mode` qualifier. Mirrors `MinesweeperUI.GameMode`'s
/// raw values without importing the UI layer (dependency direction: the
/// composition root maps `GameMode.rawValue ↔ modeRaw` at the seam).
public enum GameModeRaw {
    public static let daily = "daily"
    public static let practice = "practice"
}

public struct MinesweeperSavedGameSummary: Sendable, Equatable, Hashable, Codable, Identifiable {
    public var id: String { recordName }

    public let recordName: String
    public let difficulty: Difficulty
    /// Seed the board was generated from — required to rebuild the exact
    /// mine layout on resume (`MinesweeperSession.restore` + the
    /// `.board(difficulty:seed:mode:)` route).
    public let seed: UInt64
    public let modeRaw: String
    public let elapsedSeconds: Int
    public let lastModifiedAt: Date
    /// `"inProgress"`, `"completed"`, or `"failed"` — three-state wire shape.
    /// `"failed"` is Epic 8 (SDD-003): a daily board where the player hit a mine
    /// (`.lost`) — distinct from completed (won) and from not-yet-played.
    public let status: String

    public init(
        recordName: String,
        difficulty: Difficulty,
        seed: UInt64,
        modeRaw: String,
        elapsedSeconds: Int,
        lastModifiedAt: Date,
        status: String
    ) {
        self.recordName = recordName
        self.difficulty = difficulty
        self.seed = seed
        self.modeRaw = modeRaw
        self.elapsedSeconds = elapsedSeconds
        self.lastModifiedAt = lastModifiedAt
        self.status = status
    }
}
