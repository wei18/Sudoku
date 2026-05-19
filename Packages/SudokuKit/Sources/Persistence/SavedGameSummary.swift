// SavedGameSummary — projection of a `SavedGame` CloudKit record used at
// the protocol surface (e.g. `latestInProgress()`).
//
// Per design.md §How.2 (Private DB schema) and §How.5.4 (VM-facing types).
//
// `generatorVersion` is stored as `Int` (mirroring the CloudKit field type
// `Int(64)`). `SudokuEngine.GeneratorVersion` is a String enum (`.v1`); the
// live store maps `.v1 → 1` deterministically (see §How.2 row, plan.md 5.4).

public import Foundation

public struct SavedGameSummary: Sendable, Equatable, Hashable, Codable, Identifiable {
    public var id: String { recordName }

    public let recordName: String
    public let puzzleId: String
    /// `"daily"` or `"practice"`. Mirrors the raw string used by Telemetry
    /// (Phase 4 deviation kept primitive-only at this seam too).
    public let mode: String
    /// `"easy"` / `"medium"` / `"hard"`.
    public let difficulty: String
    public let lastModifiedAt: Date
    public let elapsedSeconds: Int
    /// `"inProgress"` or `"completed"`. See `GameSessionStatus` for the
    /// in-memory analogue; this surface stays primitive to keep the
    /// Persistence module free of GameState-only enums at the wire format.
    public let status: String
    /// `GeneratorVersion.v1 → 1`. See §How.2 row + §How.4.5 (split rule).
    public let generatorVersion: Int

    public init(
        recordName: String,
        puzzleId: String,
        mode: String,
        difficulty: String,
        lastModifiedAt: Date,
        elapsedSeconds: Int,
        status: String,
        generatorVersion: Int
    ) {
        self.recordName = recordName
        self.puzzleId = puzzleId
        self.mode = mode
        self.difficulty = difficulty
        self.lastModifiedAt = lastModifiedAt
        self.elapsedSeconds = elapsedSeconds
        self.status = status
        self.generatorVersion = generatorVersion
    }
}
