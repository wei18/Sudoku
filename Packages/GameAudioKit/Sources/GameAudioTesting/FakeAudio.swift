// Fake conformers (#330 P1) for unit tests + Previews. They record every call
// and expose scriptable state so a test can assert "played event X with haptic Y"
// or "music never started because other audio was playing" without touching
// AVFoundation / the system audio session. Import nothing beyond `GameAudio`.
//
// All three are `final class … @unchecked Sendable` with an `NSLock`-guarded
// backing store (mirroring `FakeAudioSession` below). The protocols' sync methods
// record SYNCHRONOUSLY, in call order — so a test can assert `play(A); play(B)`
// recorded exactly `[A, B]`. (An earlier `actor` version did fire-and-forget
// `Task { await record(...) }`, which did NOT guarantee order — swift6-concurrency.)

public import GameAudio
internal import Foundation

/// Records sfx events + music start/stop + volume / mute / music-enabled state.
public final class FakeSoundPlaying: SoundPlaying, @unchecked Sendable {

    private let lock = NSLock()
    private var _playedEvents: [AudioEvent] = []
    private var _startedMusicKeys: [String] = []
    private var _stopMusicCount = 0
    private var _sfxVolume: Float = 1.0
    private var _musicVolume: Float = 1.0
    private var _isMuted = false
    private var _isMusicEnabled = true
    private var _hapticsEnabled = true

    public init() {}

    public func play(_ event: AudioEvent) {
        lock.lock(); defer { lock.unlock() }
        _playedEvents.append(event)
    }

    public func playMusic(key: String) {
        lock.lock(); defer { lock.unlock() }
        _startedMusicKeys.append(key)
    }

    public func stopMusic() {
        lock.lock(); defer { lock.unlock() }
        _stopMusicCount += 1
    }

    public func setSFXVolume(_ volume: Float) {
        lock.lock(); defer { lock.unlock() }
        _sfxVolume = volume
    }

    public func setMusicVolume(_ volume: Float) {
        lock.lock(); defer { lock.unlock() }
        _musicVolume = volume
    }

    public func setMuted(_ muted: Bool) {
        lock.lock(); defer { lock.unlock() }
        _isMuted = muted
    }

    public func setMusicEnabled(_ enabled: Bool) {
        lock.lock(); defer { lock.unlock() }
        _isMusicEnabled = enabled
    }

    public func setHapticsEnabled(_ enabled: Bool) {
        lock.lock(); defer { lock.unlock() }
        _hapticsEnabled = enabled
    }

    // MARK: - Lock-guarded reads

    /// Every sfx `play(_:)` event in order.
    public var playedEvents: [AudioEvent] {
        lock.lock(); defer { lock.unlock() }; return _playedEvents
    }
    /// Keys passed to `playMusic`, in order.
    public var startedMusicKeys: [String] {
        lock.lock(); defer { lock.unlock() }; return _startedMusicKeys
    }
    /// Count of `stopMusic` calls.
    public var stopMusicCount: Int {
        lock.lock(); defer { lock.unlock() }; return _stopMusicCount
    }
    public var sfxVolume: Float {
        lock.lock(); defer { lock.unlock() }; return _sfxVolume
    }
    public var musicVolume: Float {
        lock.lock(); defer { lock.unlock() }; return _musicVolume
    }
    public var isMuted: Bool {
        lock.lock(); defer { lock.unlock() }; return _isMuted
    }
    public var isMusicEnabled: Bool {
        lock.lock(); defer { lock.unlock() }; return _isMusicEnabled
    }
    /// Latest value passed to `setHapticsEnabled` (defaults to `true`).
    public var hapticsEnabled: Bool {
        lock.lock(); defer { lock.unlock() }; return _hapticsEnabled
    }
}

/// Records every fired haptic, in order.
public final class FakeHapticPlaying: HapticPlaying, @unchecked Sendable {

    private let lock = NSLock()
    private var _playedHaptics: [HapticKind] = []

    public init() {}

    public func play(_ kind: HapticKind) {
        lock.lock(); defer { lock.unlock() }
        _playedHaptics.append(kind)
    }

    /// Every fired haptic, in order.
    public var playedHaptics: [HapticKind] {
        lock.lock(); defer { lock.unlock() }; return _playedHaptics
    }
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
