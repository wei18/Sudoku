// SudokuAudioEvents (#330 P2) — the Sudoku-owned `AudioEvent` constants.
//
// `GameAudio.AudioEvent` is game-agnostic (a string `soundKey` + optional haptic
// + channel); the event names live HERE, in the app's UI target, per the P1
// design (no Sudoku event names leak into GameAudioKit). Each `soundKey` matches
// the zen-wood asset filename generated for P3 (`place` / `complete` / `error` /
// `win`); until those assets ship, `LiveSoundPlayer` tolerates the missing file
// and no-ops (sound is silent, haptics still fire).
//
// Locked decision: haptics fire ONLY on meaningful events (section cleared /
// mistake / win) — NEVER on a plain digit placement.

internal import GameAudio

extension AudioEvent {

    /// A digit was placed into a cell. Sound only — no haptic (locked decision:
    /// plain placement never buzzes).
    static let sudokuPlace = AudioEvent(soundKey: "place", haptic: nil, channel: .sfx)

    /// A row / column / box was just completed. Medium haptic for the small win.
    static let sudokuSectionCleared = AudioEvent(soundKey: "complete", haptic: .medium, channel: .sfx)

    /// An incorrect entry (a placement that creates a conflict). Error haptic.
    static let sudokuMistake = AudioEvent(soundKey: "error", haptic: .error, channel: .sfx)

    /// The puzzle was solved. Success haptic for the full win.
    static let sudokuWin = AudioEvent(soundKey: "win", haptic: .success, channel: .sfx)

    /// #939: sticky digit-first — an armed tap landed on a non-empty cell that
    /// doesn't match the armed digit (different digit, or a given). No
    /// placement happens and the digit stays armed; this is haptic-only (no
    /// `soundKey` asset — `LiveSoundPlayer.play` fires the haptic before the
    /// asset lookup, so the empty key's expected "missing asset" no-op never
    /// blocks the light tap-absorbed feedback).
    static let sudokuArmedMismatch = AudioEvent(soundKey: "", haptic: .light, channel: .sfx)
}

/// The background-music track key for the gameplay screen. Matches the P3
/// zen-wood asset filename; silent until the asset ships.
enum SudokuAudioMusic {
    static let gameplay = "gameplay"
}
