// The game-agnostic audio value types (#330 P1). An `AudioEvent` is the unit a
// caller hands to `SoundPlaying.play(_:)`: it names a sound by string `soundKey`
// (resolved to an asset filename later — P3 ships the assets), optionally pairs a
// haptic to fire alongside, and tags a channel for volume routing.
//
// Game-agnostic by design: NO Sudoku/Minesweeper event names live here. Each app
// defines its own `AudioEvent` constants in P2 — this target only carries the
// generic shape (mirrors RemindersKit's content-neutral value types).

/// A single playable audio cue. `Hashable` so callers can de-dupe / cache, and
/// `Sendable` so it crosses isolation boundaries to the player freely.
public struct AudioEvent: Sendable, Hashable {

    /// Asset lookup key — maps to a sound filename in the player's bundle (P3).
    /// Until assets land (P1/P2), the Live player tolerates a missing file and
    /// no-ops, so an unknown key never traps.
    ///
    /// An EMPTY string is a deliberate, distinct contract: "haptic-only, no
    /// sound ever" (used by Sudoku's `sudokuArmedMismatch`, #939). Unlike a
    /// merely-unshipped key, `LiveSoundPlayer.play(_:)` short-circuits before
    /// the bundle-resolve path for `""` — no rescan, no per-call log notice —
    /// which matters for a caller that fires the event once per user
    /// interaction in a fast, repeated tap sequence.
    public let soundKey: String

    /// Optional haptic to fire alongside this sfx cue (nil = sound only).
    public let haptic: HapticKind?

    /// Which channel this cue plays on — drives which volume / mute applies.
    public let channel: AudioChannel

    public init(soundKey: String, haptic: HapticKind? = nil, channel: AudioChannel = .sfx) {
        self.soundKey = soundKey
        self.haptic = haptic
        self.channel = channel
    }
}

/// Haptic feedback flavors. Maps to `UIImpactFeedbackGenerator` /
/// `UINotificationFeedbackGenerator` styles in the Live conformer (iOS only;
/// no-op elsewhere).
public enum HapticKind: Sendable {
    case light, medium, heavy
    case success, warning, error
}

/// Audio routing channel. SFX and music carry independent volumes; music also
/// yields to other apps' audio (auto-yield) where SFX does not.
public enum AudioChannel: Sendable {
    case sfx, music
}
