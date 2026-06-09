// Fake conformers (#330 P1) for unit tests + Previews. They record every call
// and expose scriptable state so a test can assert "played event X with haptic Y"
// or "music never started because other audio was playing" without touching
// AVFoundation / the system audio session. Import nothing beyond `GameAudio`.
//
// All three are `actor`s: the protocols are `Sendable`, and actor isolation gives
// data-race-free recording with the least ceremony (swift6-concurrency). Their
// nonisolated protocol methods hop onto the actor to record.

public import GameAudio
internal import Foundation

/// Records sfx events + music start/stop + volume / mute / music-enabled state.
public actor FakeSoundPlaying: SoundPlaying {

    /// Every sfx `play(_:)` event in order.
    public private(set) var playedEvents: [AudioEvent] = []
    /// Keys passed to `playMusic`, in order.
    public private(set) var startedMusicKeys: [String] = []
    /// Count of `stopMusic` calls.
    public private(set) var stopMusicCount = 0

    public private(set) var sfxVolume: Float = 1.0
    public private(set) var musicVolume: Float = 1.0
    public private(set) var isMuted = false
    public private(set) var isMusicEnabled = true

    public init() {}

    nonisolated public func play(_ event: AudioEvent) {
        Task { await self.record(event) }
    }

    nonisolated public func playMusic(key: String) {
        Task { await self.recordMusicStart(key) }
    }

    nonisolated public func stopMusic() {
        Task { await self.recordMusicStop() }
    }

    nonisolated public func setSFXVolume(_ volume: Float) {
        Task { await self.setSFX(volume) }
    }

    nonisolated public func setMusicVolume(_ volume: Float) {
        Task { await self.setMusic(volume) }
    }

    nonisolated public func setMuted(_ muted: Bool) {
        Task { await self.setMute(muted) }
    }

    nonisolated public func setMusicEnabled(_ enabled: Bool) {
        Task { await self.setMusicEnabledState(enabled) }
    }

    // MARK: - Recording (actor-isolated)

    private func record(_ event: AudioEvent) { playedEvents.append(event) }
    private func recordMusicStart(_ key: String) { startedMusicKeys.append(key) }
    private func recordMusicStop() { stopMusicCount += 1 }
    private func setSFX(_ volume: Float) { sfxVolume = volume }
    private func setMusic(_ volume: Float) { musicVolume = volume }
    private func setMute(_ muted: Bool) { isMuted = muted }
    private func setMusicEnabledState(_ enabled: Bool) { isMusicEnabled = enabled }
}

/// Records every fired haptic, in order.
public actor FakeHapticPlaying: HapticPlaying {

    public private(set) var playedHaptics: [HapticKind] = []

    public init() {}

    nonisolated public func play(_ kind: HapticKind) {
        Task { await self.record(kind) }
    }

    private func record(_ kind: HapticKind) { playedHaptics.append(kind) }
}

/// Scriptable audio session: set `isOtherAudioPlaying` to drive the music
/// auto-yield path, and inspect whether `configureAmbient` ran.
public final class FakeAudioSession: AudioSessionConfiguring, @unchecked Sendable {

    private let lock = NSLock()
    private var _isOtherAudioPlaying: Bool
    private var _didConfigure = false

    /// - Parameter isOtherAudioPlaying: seed for the auto-yield read (defaults to
    ///   `false` — nothing else playing).
    public init(isOtherAudioPlaying: Bool = false) {
        self._isOtherAudioPlaying = isOtherAudioPlaying
    }

    public func configureAmbient() {
        lock.lock(); defer { lock.unlock() }
        _didConfigure = true
    }

    public var isOtherAudioPlaying: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _isOtherAudioPlaying }
        set { lock.lock(); defer { lock.unlock() }; _isOtherAudioPlaying = newValue }
    }

    /// Whether `configureAmbient()` was called.
    public var didConfigure: Bool {
        lock.lock(); defer { lock.unlock() }; return _didConfigure
    }
}
