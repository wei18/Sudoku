// The three protocol seams (#330 P1). Wrapping the awkward-to-fake AVFoundation
// playback, system audio session, and UIKit haptics behind protocols lets UI /
// logic / tests depend on abstractions and swap Live ↔ Noop ↔ Fake
// (swift-testing-baseline protocol-injected fakes). `AVFoundation` / `AVFAudio` /
// `UIKit` are imported only by the Live conformers, never here.

/// Seam 1 — sound playback. The single entry point callers reach for: fire an
/// sfx event (which may carry a haptic), control looping background music, and
/// adjust the live volumes / mute / music-enabled flags as the user changes
/// settings.
public protocol SoundPlaying: Sendable {

    /// Play a one-shot sfx cue. If the event carries a `haptic`, the Live impl
    /// also fires it via the injected `HapticPlaying`.
    func play(_ event: AudioEvent)

    /// Start (or restart) the single looping background-music track for `key`.
    /// The Live impl auto-yields: if another app is already playing audio it does
    /// NOT start (so we never stomp the user's podcast / music).
    func playMusic(key: String)

    /// Stop the looping background-music track.
    func stopMusic()

    /// Set the sfx channel volume (0...1).
    func setSFXVolume(_ volume: Float)

    /// Set the music channel volume (0...1).
    func setMusicVolume(_ volume: Float)

    /// Master mute — silences all output without losing the per-channel volumes.
    func setMuted(_ muted: Bool)

    /// Toggle background music on/off. When turned off the Live impl stops any
    /// playing track; turning it back on does not auto-resume (the caller decides).
    func setMusicEnabled(_ enabled: Bool)
}

/// Seam 2 — haptics. Wraps the UIKit feedback generators so non-iOS / tests get
/// a clean no-op.
public protocol HapticPlaying: Sendable {

    /// Fire a single haptic of the given kind.
    func play(_ kind: HapticKind)
}

/// Seam 3 — audio session. Wraps `AVAudioSession` so the player can configure
/// the ambient (mix-with-others) category and check whether other audio is
/// playing before starting music (the auto-yield read).
public protocol AudioSessionConfiguring: Sendable {

    /// Configure the session for ambient game audio that mixes with other apps.
    /// No-op on platforms without `AVAudioSession` (macOS).
    func configureAmbient()

    /// Whether another app is currently playing audio (drives music auto-yield).
    /// Always `false` where `AVAudioSession` is unavailable (macOS).
    var isOtherAudioPlaying: Bool { get }
}
