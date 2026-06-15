// Game2048LeaderboardID — daily leaderboard identifier for Tiles2048.
//
// 2048 has a single daily board (no difficulty), so there is exactly one
// daily leaderboard (versus MS's three per-difficulty boards).
//
// OQ-004-3: Daily = high-score on shared seed. GameKit submits score via
// `submitScore(leaderboardId:elapsedSeconds:)` where the "elapsed" parameter
// carries the game score (the ASC formatter is INTEGER, not ELAPSED_TIME;
// note for M5 ASC config: configure score format as INTEGER with high=better).
//
// ID MUST stay byte-equal to the ASCRegister `Config.leaderboards(for:
// .tiles2048)` entry (to be added in a follow-up — ASCRegister currently
// only covers sudoku/minesweeper). Until that PR lands, the ID here is the
// single source of truth.
//
// NOTE: ASC registration of this leaderboard (App Store Connect Game Center
// catalog) is a user-owned step at M5. The code compiles and runs test-safe
// without it — the GameCenterClient seam is nil-safe.

public enum Game2048LeaderboardID {

    /// Bundle-id-rooted prefix. Must equal the ASCRegister config entry when added.
    public static let prefix = "com.wei18.tiles2048.leaderboard"

    /// Current generator family suffix. Bumped alongside any board-generator
    /// version change (mirrors Sudoku / Minesweeper versionSuffix).
    public static let versionSuffix = "v1"

    /// Single daily leaderboard — high score on the shared daily seed.
    /// Format: INTEGER, higher = better (ASC config at M5).
    public static let daily = "\(prefix).daily.\(versionSuffix)"
}
