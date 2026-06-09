// AudioSettingsModel — the shared Settings-screen audio entry driver (#330 P1).
//
// Mirrors `ReminderSettingsModel`: a `@MainActor @Observable` model whose
// persistence is INJECTED as get/set closures (NOT a hardcoded `UserDefaults`),
// so Sudoku and Minesweeper each bridge to their own store / key prefix with no
// shared store type and no cross-app key collision. It is the single shared
// driver for BOTH apps' Settings audio section (Minesweeper mirrors Sudoku).
//
// Every setter does two things: persist via the injected closure AND push the new
// value to the injected live `SoundPlaying`, so moving a slider updates the
// running player immediately. The player is OPTIONAL (`(any SoundPlaying)?`) so
// Previews / audio-disabled hosts pass `nil` — every push is nil-safe.
//
// Defaults (spec): BGM default ON (`musicEnabled = true`), `hapticsEnabled = true`,
// `isMuted = false`, volumes `0.7`. The host's persistence closures own the
// stored defaults; this model only seeds its in-memory properties from them.
//
// It depends ONLY on the `GameAudio.SoundPlaying` seam + injected closures — it
// never imports `AVFoundation` (restricted to GameAudioKit's Live files).

public import SwiftUI
public import GameAudio

@MainActor
@Observable
public final class AudioSettingsModel {

    /// Background-music channel volume (0...1). `didSet` persists + pushes to the
    /// live player (NOT during `init`, where the stored property is set directly).
    public var musicVolume: Double {
        didSet {
            setMusicVolume(musicVolume)
            player?.setMusicVolume(Float(musicVolume))
        }
    }

    /// Sound-effects channel volume (0...1).
    public var sfxVolume: Double {
        didSet {
            setSFXVolume(sfxVolume)
            player?.setSFXVolume(Float(sfxVolume))
        }
    }

    /// Master mute — silences all output without losing the per-channel volumes.
    public var isMuted: Bool {
        didSet {
            setMuted(isMuted)
            player?.setMuted(isMuted)
        }
    }

    /// Whether haptic feedback is on. Persists + pushes to the live player, which
    /// gates per-event haptics on this flag independently of master mute (#330 P2).
    public var hapticsEnabled: Bool {
        didSet {
            setHapticsEnabled(hapticsEnabled)
            player?.setHapticsEnabled(hapticsEnabled)
        }
    }

    /// Whether background music is on.
    public var musicEnabled: Bool {
        didSet {
            setMusicEnabled(musicEnabled)
            player?.setMusicEnabled(musicEnabled)
        }
    }

    @ObservationIgnored private let player: (any SoundPlaying)?
    @ObservationIgnored private let setMusicVolume: (Double) -> Void
    @ObservationIgnored private let setSFXVolume: (Double) -> Void
    @ObservationIgnored private let setMuted: (Bool) -> Void
    @ObservationIgnored private let setHapticsEnabled: (Bool) -> Void
    @ObservationIgnored private let setMusicEnabled: (Bool) -> Void

    /// - Parameters:
    ///   - player: the live `SoundPlaying` to push changes to (nil for Previews /
    ///     audio-disabled hosts — every push is nil-safe).
    ///   - getMusicVolume / setMusicVolume … : the persistence seam, injected per
    ///     property so the model stays store-agnostic. The host supplies the
    ///     stored defaults (BGM on, haptics on, not muted, volumes 0.7).
    public init(
        player: (any SoundPlaying)? = nil,
        getMusicVolume: () -> Double,
        setMusicVolume: @escaping (Double) -> Void,
        getSFXVolume: () -> Double,
        setSFXVolume: @escaping (Double) -> Void,
        getIsMuted: () -> Bool,
        setMuted: @escaping (Bool) -> Void,
        getHapticsEnabled: () -> Bool,
        setHapticsEnabled: @escaping (Bool) -> Void,
        getMusicEnabled: () -> Bool,
        setMusicEnabled: @escaping (Bool) -> Void
    ) {
        self.player = player
        self.setMusicVolume = setMusicVolume
        self.setSFXVolume = setSFXVolume
        self.setMuted = setMuted
        self.setHapticsEnabled = setHapticsEnabled
        self.setMusicEnabled = setMusicEnabled
        // Seed in-memory state from persistence (direct assignment — does not fire
        // didSet, so seeding never re-persists or re-pushes).
        self.musicVolume = getMusicVolume()
        self.sfxVolume = getSFXVolume()
        self.isMuted = getIsMuted()
        self.hapticsEnabled = getHapticsEnabled()
        self.musicEnabled = getMusicEnabled()
    }
}
