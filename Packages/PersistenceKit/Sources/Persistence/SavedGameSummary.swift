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
//
// `boardState` (#1017): the raw 81-char encoded board string, already
// fetched as part of the `SavedGame` record `latestInProgress()` reads —
// surfaced here (rather than discarded) so a `fetchResume` closure can build
// a `BoardPreview` without a second CloudKit round-trip. `nil` when the
// record is missing/malformed; callers must degrade gracefully, never crash.

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
    /// 81-char encoded board ('.' for blank, digit otherwise). See #1017 note above.
    public let boardState: String?

    public init(
        recordName: String,
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty,
        lastModifiedAt: Date,
        elapsedSeconds: Int,
        status: String,
        generatorVersion: Int,
        boardState: String? = nil
    ) {
        self.recordName = recordName
        self.puzzleId = puzzleId
        self.mode = mode
        self.difficulty = difficulty
        self.lastModifiedAt = lastModifiedAt
        self.elapsedSeconds = elapsedSeconds
        self.status = status
        self.generatorVersion = generatorVersion
        self.boardState = boardState
    }
}
