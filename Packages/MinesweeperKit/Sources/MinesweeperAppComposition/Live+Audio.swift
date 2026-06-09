// Live+Audio.swift — Minesweeper composition: the audio-settings builder,
// extracted from Live.swift to keep that file under the 400-line lint ceiling
// (#330 P2 added the live audio-stack construction). Pure relocation — the
// builder is unchanged; only its access level moved from `private` to
// `internal` so `.live()` in Live.swift can call it across files.

internal import Foundation
internal import GameAudio
internal import SettingsUI

extension MinesweeperAppComposition {
    /// #330 P2: build the shared `AudioSettingsModel` over the live player +
    /// device-local `UserDefaults`. Mirrors the reminder-settings persistence
    /// shape: get/set closures over an MS-namespaced key prefix, so MS's audio
    /// preferences never collide with Sudoku's and stay device-local (NOT
    /// CloudKit-synced — audio is a per-device setting). Spec defaults are applied
    /// on first run via the absent-key gates: BGM on, haptics on, not muted,
    /// volumes 0.7. Pushing each change to the player keeps the running audio in
    /// sync as the user moves a slider.
    static func makeAudioSettings(
        player: any SoundPlaying,
        defaults: UserDefaults,
        keyPrefix: String
    ) -> AudioSettingsModel {
        let musicVolumeKey = keyPrefix + "musicVolume"
        let sfxVolumeKey = keyPrefix + "sfxVolume"
        let mutedKey = keyPrefix + "muted"
        let hapticsKey = keyPrefix + "hapticsEnabled"
        let musicEnabledKey = keyPrefix + "musicEnabled"
        // `UserDefaults.double` / `.bool` return 0 / false for absent keys, which
        // is indistinguishable from a deliberately-stored 0 / off — gate on
        // presence so the spec defaults seed cleanly on first run.
        func storedDouble(_ key: String, default fallback: Double) -> Double {
            defaults.object(forKey: key) != nil ? defaults.double(forKey: key) : fallback
        }
        func storedBool(_ key: String, default fallback: Bool) -> Bool {
            defaults.object(forKey: key) != nil ? defaults.bool(forKey: key) : fallback
        }
        return AudioSettingsModel(
            player: player,
            getMusicVolume: { storedDouble(musicVolumeKey, default: 0.7) },
            setMusicVolume: { defaults.set($0, forKey: musicVolumeKey) },
            getSFXVolume: { storedDouble(sfxVolumeKey, default: 0.7) },
            setSFXVolume: { defaults.set($0, forKey: sfxVolumeKey) },
            getIsMuted: { storedBool(mutedKey, default: false) },
            setMuted: { defaults.set($0, forKey: mutedKey) },
            getHapticsEnabled: { storedBool(hapticsKey, default: true) },
            setHapticsEnabled: { defaults.set($0, forKey: hapticsKey) },
            getMusicEnabled: { storedBool(musicEnabledKey, default: true) },
            setMusicEnabled: { defaults.set($0, forKey: musicEnabledKey) }
        )
    }
}
