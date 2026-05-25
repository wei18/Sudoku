// PuzzleIdentity — product-layer puzzle naming (docs/v1/design.md §How.4.3).
//
// `puzzleId` is the user-facing key used across Persistence (`SavedGame`),
// GameCenter (leaderboard / achievement payloads) and Telemetry. It is
// deterministic content with no PII — `OSLog .public`-safe.
//
// M5 (issue #65): `kind` (now `Mode`) + `difficulty` (now `Difficulty`)
// are typed at the API surface. The `puzzleId` string still encodes them
// as `.rawValue` for wire-format compatibility.

public import Foundation
public import SudokuEngine

public struct PuzzleIdentity: Sendable, Equatable, Hashable, Codable {
    public let puzzleId: String
    public let kind: Mode
    public let difficulty: Difficulty

    public init(puzzleId: String, kind: Mode, difficulty: Difficulty) {
        self.puzzleId = puzzleId
        self.kind = kind
        self.difficulty = difficulty
    }

    /// Daily puzzle: id = "YYYY-MM-DD-{difficulty}" using the UTC date floor.
    public static func daily(date: Date, difficulty: Difficulty) -> PuzzleIdentity {
        let day = UTCDay.string(from: date)
        return PuzzleIdentity(
            puzzleId: "\(day)-\(difficulty.rawValue)",
            kind: .daily,
            difficulty: difficulty
        )
    }

    /// Practice puzzle: id = "practice-{crockfordBase32(salt)}-{difficulty}".
    /// Crockford alphabet (no I/L/O/U) keeps ids unambiguous in bug reports.
    public static func practice(salt: UInt64, difficulty: Difficulty) -> PuzzleIdentity {
        let body = CrockfordBase32.encode(salt)
        return PuzzleIdentity(
            puzzleId: "practice-\(body)-\(difficulty.rawValue)",
            kind: .practice,
            difficulty: difficulty
        )
    }
}

// MARK: - Internal helpers

/// Crockford base32 encoder for `UInt64`. Output is the minimal representation
/// of the integer in big-endian base32; salt=0 → "0".
internal enum CrockfordBase32 {
    static let alphabet: [Character] = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    static func encode(_ value: UInt64) -> String {
        if value == 0 { return "0" }
        var remaining = value
        var chars: [Character] = []
        while remaining > 0 {
            let index = Int(remaining & 0x1F)
            chars.append(alphabet[index])
            remaining >>= 5
        }
        return String(chars.reversed())
    }
}
