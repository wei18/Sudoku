// Minesweeper's per-app audio event constants (#330 P2).
//
// `AudioEvent` is game-agnostic (GameAudioKit ships only the shape — no
// Sudoku/Minesweeper names live there). Each app owns its event vocabulary; this
// is Minesweeper's. The `soundKey`s match the zen-wood assets generated for P3
// (`reveal` / `flag` / `floodClear` / `explosion` / `win`); until P3 lands the
// Live player tolerates the missing files and no-ops (silent), so firing these is
// safe today.
//
// Haptic policy (LOCKED decision): haptics fire ONLY on the meaningful,
// lower-frequency events — a flood-clear, hitting a mine, and winning. Routine
// per-tap actions (a single reveal, a flag toggle) carry NO haptic: peppering a
// tap-heavy game with feedback on every cell would be noise, not signal.

public import GameAudio

extension AudioEvent {

    /// Revealing a single (non-flooding) cell. SFX only — no haptic on a routine tap.
    public static let minesweeperReveal = AudioEvent(soundKey: "reveal", haptic: nil, channel: .sfx)

    /// Toggling a flag on/off. SFX only — no haptic on a routine tap.
    public static let minesweeperFlag = AudioEvent(soundKey: "flag", haptic: nil, channel: .sfx)

    /// A reveal that flood-cleared a region of empty cells. Medium haptic marks
    /// the satisfying chain-clear.
    public static let minesweeperFloodClear = AudioEvent(soundKey: "floodClear", haptic: .medium, channel: .sfx)

    /// Detonating a mine (loss). Error haptic underscores the failure moment.
    public static let minesweeperExplosion = AudioEvent(soundKey: "explosion", haptic: .error, channel: .sfx)

    /// Clearing the board (win). Success haptic celebrates the solve.
    public static let minesweeperWin = AudioEvent(soundKey: "win", haptic: .success, channel: .sfx)
}
