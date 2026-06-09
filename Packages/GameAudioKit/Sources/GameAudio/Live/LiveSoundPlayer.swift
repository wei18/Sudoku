// LiveSoundPlayer — the production `SoundPlaying`, wrapping AVFoundation's
// `AVAudioPlayer`.
//
// RESTRICTED IMPORT: the only file allowed to import `AVFoundation`. The seam
// keeps every UI / logic / test layer free of the framework — same discipline as
// UserNotifications→Reminders/Live.
//
// Asset tolerance (#330 P1): P1 ships with NO audio assets, so a missing file for
// a `soundKey` is the NORMAL path until P3. The player logs via `os.Logger` and
// no-ops — it never traps. Assets are loaded by `soundKey` from an injected
// `Bundle`.
//
// State model: `AVAudioPlayer` is not `Sendable`, so all mutable state (the sfx
// player cache, the single looping music player, volumes, mute / music-enabled
// flags) lives behind an `NSLock`. This keeps the public type `Sendable` without
// `@unchecked` leaking to callers, and makes `play(_:)` callable from any
// isolation.
//
// Music auto-yield: when `playMusic` is asked to start while
// `session.isOtherAudioPlaying`, it does NOT start (so we never stomp the user's
// own audio). P2 can re-check the session and retry.

// `Foundation` is `public` (not `internal`) because `Bundle` appears in the
// public `init` default argument (`bundle: Bundle = .main`).
public import Foundation
internal import os

#if canImport(AVFoundation)
internal import AVFoundation
#endif

// `@unchecked Sendable`: all mutable state is guarded by `lock`. `AVAudioPlayer`
// isn't `Sendable`, so the compiler can't verify this automatically — the lock is
// the manual guarantee.
public final class LiveSoundPlayer: SoundPlaying, @unchecked Sendable {

    private let bundle: Bundle
    private let session: any AudioSessionConfiguring
    private let haptics: any HapticPlaying
    private let logger: Logger

    /// Guards all mutable state below. `AVAudioPlayer` isn't `Sendable`; the lock
    /// makes the whole type `Sendable` (no `@unchecked` on the public surface).
    private let lock = NSLock()

    #if canImport(AVFoundation)
    /// Small reuse cache of one player per `soundKey` (keeps decoded audio warm so
    /// rapid taps don't re-decode). Missing-asset keys are never cached.
    private var sfxPlayers: [String: AVAudioPlayer] = [:]
    /// The single looping background-music player.
    private var musicPlayer: AVAudioPlayer?
    #endif

    private var sfxVolume: Float = 1.0
    private var musicVolume: Float = 1.0
    private var isMuted = false
    private var isMusicEnabled = true
    private var hapticsEnabled = true

    /// - Parameters:
    ///   - bundle: where sound files are looked up by `soundKey` (defaults to the
    ///     host app's main bundle).
    ///   - session: the audio session seam (auto-yield check + ambient config).
    ///   - haptics: the haptic seam — fired for an sfx event that carries a haptic.
    ///   - subsystem: OSLog subsystem — pass the host app's bundle id
    ///     (oslog-logger-defaults).
    public init(
        bundle: Bundle = .main,
        session: any AudioSessionConfiguring,
        haptics: any HapticPlaying,
        subsystem: String = "GameAudio"
    ) {
        self.bundle = bundle
        self.session = session
        self.haptics = haptics
        self.logger = Logger(subsystem: subsystem, category: "GameAudio")
    }

    // MARK: - SFX

    public func play(_ event: AudioEvent) {
        // Contract (#330 P2): haptics are governed by `hapticsEnabled` ONLY — master
        // mute (`isMuted`) silences audio, NOT haptics. The haptic also fires
        // regardless of whether the sound asset exists (a missing asset is the
        // normal P1 path, but the haptic still gives feedback).
        if let haptic = event.haptic {
            lock.lock()
            let fireHaptic = hapticsEnabled
            lock.unlock()
            if fireHaptic { haptics.play(haptic) }
        }

        #if canImport(AVFoundation)
        lock.lock()
        defer { lock.unlock() }

        guard !isMuted else { return }

        guard let player = resolveSFXPlayerLocked(key: event.soundKey) else {
            return // missing asset — already logged; no-op (P1 has no assets)
        }
        player.volume = event.channel == .music ? musicVolume : sfxVolume
        player.currentTime = 0
        player.play()
        #endif
    }

    // MARK: - Music

    public func playMusic(key: String) {
        // Auto-yield: never start over another app's audio.
        if session.isOtherAudioPlaying {
            logger.debug("music suppressed — other audio is playing (auto-yield)")
            return
        }

        #if canImport(AVFoundation)
        lock.lock()
        defer { lock.unlock() }

        guard isMusicEnabled, !isMuted else { return }

        guard let player = makePlayerLocked(key: key) else {
            return // missing asset — already logged; no-op (P1 has no assets)
        }
        player.numberOfLoops = -1 // loop indefinitely
        player.volume = musicVolume
        musicPlayer = player
        player.play()
        #endif
    }

    public func stopMusic() {
        #if canImport(AVFoundation)
        lock.lock()
        defer { lock.unlock() }
        musicPlayer?.stop()
        musicPlayer = nil
        #endif
    }

    // MARK: - Volume / mute

    public func setSFXVolume(_ volume: Float) {
        lock.lock()
        defer { lock.unlock() }
        sfxVolume = clamp(volume)
    }

    public func setMusicVolume(_ volume: Float) {
        lock.lock()
        defer { lock.unlock() }
        musicVolume = clamp(volume)
        #if canImport(AVFoundation)
        musicPlayer?.volume = musicVolume
        #endif
    }

    public func setMuted(_ muted: Bool) {
        lock.lock()
        defer { lock.unlock() }
        isMuted = muted
        #if canImport(AVFoundation)
        if muted { musicPlayer?.pause() } else if isMusicEnabled { musicPlayer?.play() }
        #endif
    }

    public func setMusicEnabled(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        isMusicEnabled = enabled
        #if canImport(AVFoundation)
        if !enabled {
            // Turning music off stops any playing track; turning it back on does
            // NOT auto-resume (the caller decides when to restart).
            musicPlayer?.stop()
            musicPlayer = nil
        }
        #endif
    }

    public func setHapticsEnabled(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        hapticsEnabled = enabled
    }

    // MARK: - Helpers

    private func clamp(_ volume: Float) -> Float { min(1, max(0, volume)) }

    #if canImport(AVFoundation)
    /// Resolve (and cache) the sfx player for `key`. Returns `nil` when the asset
    /// is missing — logged once per lookup, no trap (P1 has no assets).
    private func resolveSFXPlayerLocked(key: String) -> AVAudioPlayer? {
        if let cached = sfxPlayers[key] { return cached }
        guard let player = makePlayerLocked(key: key) else { return nil }
        sfxPlayers[key] = player
        return player
    }

    /// Build an `AVAudioPlayer` for `key` by searching the bundle for any of the
    /// common audio extensions. Missing asset → log + `nil`.
    private func makePlayerLocked(key: String) -> AVAudioPlayer? {
        guard let url = audioURL(for: key) else {
            logger.notice("audio asset missing for key \(key, privacy: .public) — no-op (expected pre-P3)")
            return nil
        }
        do {
            return try AVAudioPlayer(contentsOf: url)
        } catch {
            logger.error("failed to load audio \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Search the injected bundle for `key` across the audio extensions we ship.
    private func audioURL(for key: String) -> URL? {
        for ext in ["caf", "wav", "m4a", "aif", "aiff", "mp3"] {
            if let url = bundle.url(forResource: key, withExtension: ext) {
                return url
            }
        }
        return nil
    }
    #endif
}
