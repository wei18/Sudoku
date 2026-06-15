// Game2048SavedGameSummary — projection of a Tiles2048 `SavedGame`
// CloudKit record used at the store surface (`latestInProgress()`).
//
// 2048-native by design: the shared resume seam consumes a
// game-agnostic `ResumeCandidate<AppRoute>` built from this summary by
// the `fetchResume` closure, so this type does NOT reuse the Sudoku-typed
// `Persistence.SavedGameSummary`.
//
// `modeRaw` stays a raw `String` ("daily" / "practice") so this target
// does not import Game2048UI, where the `GameMode` enum lives.
// Mirrors MinesweeperSavedGameSummary exactly.

public import Foundation

/// Wire values for the `mode` qualifier. Mirrors `Game2048UI.GameMode`'s
/// raw values without importing the UI layer.
public enum Game2048GameModeRaw {
    public static let daily = "daily"
    public static let practice = "practice"
}

public struct Game2048SavedGameSummary: Sendable, Equatable, Hashable, Codable, Identifiable {
    public var id: String { recordName }

    public let recordName: String
    public let seed: UInt64
    public let modeRaw: String
    public let score: Int
    public let moveCount: Int
    public let elapsedSeconds: Int
    public let lastModifiedAt: Date
    /// `"inProgress"` or `"completed"` — two-state (OQ-004-3: no Failed state).
    public let status: String

    public init(
        recordName: String,
        seed: UInt64,
        modeRaw: String,
        score: Int,
        moveCount: Int,
        elapsedSeconds: Int,
        lastModifiedAt: Date,
        status: String
    ) {
        self.recordName = recordName
        self.seed = seed
        self.modeRaw = modeRaw
        self.score = score
        self.moveCount = moveCount
        self.elapsedSeconds = elapsedSeconds
        self.lastModifiedAt = lastModifiedAt
        self.status = status
    }
}
