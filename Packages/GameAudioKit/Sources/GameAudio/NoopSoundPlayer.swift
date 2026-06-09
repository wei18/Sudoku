// Noop conformers (#330 P1). Production-safe no-ops for audio-disabled hosts and
// for SwiftUI Previews. Import nothing — pure protocol satisfaction.

/// Drops every playback / control call on the floor.
public struct NoopSoundPlaying: SoundPlaying {

    public init() {}

    public func play(_ event: AudioEvent) {}
    public func playMusic(key: String) {}
    public func stopMusic() {}
    public func setSFXVolume(_ volume: Float) {}
    public func setMusicVolume(_ volume: Float) {}
    public func setMuted(_ muted: Bool) {}
    public func setMusicEnabled(_ enabled: Bool) {}
    public func setHapticsEnabled(_ enabled: Bool) {}
}

/// Fires no haptics.
public struct NoopHapticPlaying: HapticPlaying {

    public init() {}

    public func play(_ kind: HapticKind) {}
}

/// Reports no other audio playing; configuring the session is a no-op.
public struct NoopAudioSession: AudioSessionConfiguring {

    public init() {}

    public func configureAmbient() {}

    public var isOtherAudioPlaying: Bool { false }
}
