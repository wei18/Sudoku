// MakeGameApp+Helpers — boot + audio helpers for `makeGameApp` (#556).
//
// Split out of `MakeGameApp.swift` to keep that file under the 400-line gate.

internal import Foundation
internal import Telemetry
internal import MonetizationCore
internal import AdsAdMob
internal import GameAudio
internal import SettingsUI

// MARK: - bootMonetization

/// App-launch monetization boot. Runs UMP consent → AdMob SDK initialize.
/// iOS-only: AdMob / UMP are iOS xcframeworks. On macOS returns immediately.
func bootMonetization(adProvider: any AdProvider, telemetry: Telemetry) async {
    #if !os(iOS)
    return
    #else
    let bridges = MonetizationBootBridges.live(adProvider: adProvider)
    let telemetryHandle = telemetry
    let coordinator = MonetizationBootCoordinator(
        bridges: bridges,
        log: { outcome in
            if !outcome.succeeded {
                Task {
                    await telemetryHandle.observe(
                        .errorOccurred(
                            source: "MonetizationBoot",
                            code: outcome.step.rawValue,
                            message: outcome.errorDescription ?? "unknown"
                        )
                    )
                }
            } else {
                print("[MonetizationBoot] step=\(outcome.step.rawValue) succeeded")
            }
        }
    )
    await coordinator.boot()
    #endif
}

// MARK: - Audio settings helper

/// Builds an `AudioSettingsModel` backed by `UserDefaults.standard` under
/// `keyPrefix.*` keys. Defaults match the spec: BGM on, haptics on, not muted,
/// volumes 0.7. Each setter fans out to the injected `player`.
@MainActor
func makeAudioSettings(player: any SoundPlaying, keyPrefix: String) -> AudioSettingsModel {
    let defaults = UserDefaults.standard
    let musicVolumeKey = "\(keyPrefix).musicVolume"
    let sfxVolumeKey = "\(keyPrefix).sfxVolume"
    let mutedKey = "\(keyPrefix).isMuted"
    let hapticsKey = "\(keyPrefix).hapticsEnabled"
    let musicEnabledKey = "\(keyPrefix).musicEnabled"

    func volume(_ key: String) -> Double {
        defaults.object(forKey: key) == nil ? 0.7 : defaults.double(forKey: key)
    }
    func flag(_ key: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    return AudioSettingsModel(
        player: player,
        getMusicVolume: { volume(musicVolumeKey) },
        setMusicVolume: { defaults.set($0, forKey: musicVolumeKey) },
        getSFXVolume: { volume(sfxVolumeKey) },
        setSFXVolume: { defaults.set($0, forKey: sfxVolumeKey) },
        getIsMuted: { flag(mutedKey, default: false) },
        setMuted: { defaults.set($0, forKey: mutedKey) },
        getHapticsEnabled: { flag(hapticsKey, default: true) },
        setHapticsEnabled: { defaults.set($0, forKey: hapticsKey) },
        getMusicEnabled: { flag(musicEnabledKey, default: true) },
        setMusicEnabled: { defaults.set($0, forKey: musicEnabledKey) }
    )
}
