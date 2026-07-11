// MinesweeperPracticeIdentity — per-game unique practice-mode personal-record
// puzzleId (#705).
//
// MS practice `SavedGame` recordNames stay a deliberate singleton
// (`practice-{difficulty}`, `MinesweeperSavedGameStore.recordName(practice:)`)
// — a new practice game overwrites the old resumable slot by design. That
// singleton can't double as the personal-record dedup key: every practice
// win would collapse into one `completedPuzzleIds` entry (stuck
// `completedCount == 1`, `bestTimeSeconds` frozen at the first win).
//
// Instead this type derives a per-game unique id from the board's own
// generation `seed` (`MinesweeperSessionSnapshot.seed`): every new-practice
// callsite already mints a fresh `UInt64.random(in:)` seed once per game
// (`MinesweeperPracticeHubView.start()`, `LiveRouteFactory`'s Play Again
// closure), and that seed is already persisted through save and reconstructed
// verbatim by `MinesweeperSession.restore(from:)` (it has to be — it's what
// reproduces the exact mine layout). Reusing it means no new snapshot field,
// no legacy-decode fallback, and no `MinesweeperSavedGameStore.currentSchemaVersion`
// bump: a resumed practice game restores the same seed and therefore derives
// the exact same puzzleId, satisfying the "resume + win dedups as the same
// game" requirement for free.
//
// Format mirrors Sudoku's `PuzzleIdentity.practice(salt:difficulty:)`
// (Packages/SudokuKit/Sources/SudokuPersistence/PuzzleIdentity.swift):
// `"practice-{crockfordBase32(seed)}-{difficulty.rawValue}"`.

public import MinesweeperEngine

public enum MinesweeperPracticeIdentity {
    /// `"practice-{crockfordBase32(seed)}-{difficulty.rawValue}"` — the
    /// personal-record dedup key for a practice-mode win. `seed` is the
    /// board's own generation seed (`MinesweeperSessionSnapshot.seed`), unique
    /// per new practice game and stable across save/resume.
    public static func puzzleId(seed: UInt64, difficulty: Difficulty) -> String {
        "practice-\(MinesweeperCrockfordBase32.encode(seed))-\(difficulty.rawValue)"
    }
}

// MARK: - Crockford base32

/// Crockford base32 encoder for `UInt64`, duplicated from
/// `SudokuPersistence.PuzzleIdentity`'s `internal CrockfordBase32`
/// (Packages/SudokuKit/Sources/SudokuPersistence/PuzzleIdentity.swift) — that
/// type is `internal` to its own module and SudokuPersistence isn't a
/// dependency here, so it can't be imported directly. Kept byte-for-byte
/// identical on purpose; `MinesweeperCrockfordBase32Tests` pins shared vectors
/// against Sudoku's documented outputs to catch cross-app drift. Output is
/// the minimal representation of the integer in big-endian base32; salt=0 →
/// "0".
enum MinesweeperCrockfordBase32 {
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
