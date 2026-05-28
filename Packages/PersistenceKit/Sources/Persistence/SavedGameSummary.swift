// SavedGameSummary — projection of a `SavedGame` CloudKit record used at
// the protocol surface (e.g. `latestInProgress()`).
//
// Per docs/v1/design.md §How.2 (Private DB schema) and §How.5.4 (VM-facing types).
//
// `generatorVersion` is stored as `Int` (mirroring the CloudKit field type
// `Int(64)`). `SudokuEngine.GeneratorVersion` is a String enum (`.v1`); the
// live store maps `.v1 → 1` deterministically (see §How.2 row, plan.md 5.4).
//
// M5 (issue #65): `mode` / `difficulty` are typed `Mode` / `Difficulty`
// here at the protocol surface. The CK wire format still stores them as
// raw `String` (`.rawValue`) — see `SavedGameMapper`. `status` stays a
// String here because its 2-state wire shape ("inProgress" / "completed")
// is intentionally narrower than the 5-state `GameSessionStatus` enum.

public import Foundation
public import SudokuEngine

public struct SavedGameSummary: Sendable, Equatable, Hashable, Codable, Identifiable {
    public var id: String { recordName }

    public let recordName: String
    public let puzzleId: String
    public let mode: Mode
    public let difficulty: Difficulty
    public let lastModifiedAt: Date
    public let elapsedSeconds: Int
    /// `"inProgress"` or `"completed"`. See `GameSessionStatus` for the
    /// in-memory analogue; this surface stays primitive because the wire
    /// schema only distinguishes the 2 archival states.
    public let status: String
    /// `GeneratorVersion.v1 → 1`. See §How.2 row + §How.4.5 (split rule).
    public let generatorVersion: Int

    public init(
        recordName: String,
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty,
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
