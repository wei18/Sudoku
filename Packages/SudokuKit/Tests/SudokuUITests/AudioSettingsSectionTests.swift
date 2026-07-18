// AudioSettingsSectionTests — #879 (F-10 from #874's sweep report).
//
// Master Sound mute (`isMuted`) previously dimmed the volume sliders via
// `.disabled(isMuted...)` but left `musicEnabledRow` / `hapticsRow` fully
// live-looking right next to them — a contradictory affordance within one
// `Section`. `LiveSoundPlayer` settles the semantics:
//   - `playMusic` gates on `isMusicEnabled && !isMuted` — flipping
//     `musicEnabled` while muted has ZERO audible effect, so `musicEnabledRow`
//     must visually agree with the (already-disabled) `musicVolumeRow`.
//   - `play`'s haptic branch gates on `hapticsEnabled` ONLY, independent of
//     `isMuted` (#330 P2 contract) — `hapticsRow` must stay live under mute.
// These two isolated-Section snapshots pin that asymmetric state matrix.

import Foundation
import SnapshotTesting
import SwiftUI
import Testing

import GameAudio
import GameAudioTesting
@testable import SudokuUI
import SettingsUI

@MainActor
@Suite("AudioSettingsSection — master-mute state matrix (#879)")
struct AudioSettingsSectionTests {

    /// Backing store for the model's injected persistence closures — a plain
    /// mutable struct is enough since these snapshots never round-trip.
    final class Store {
        var musicVolume = 0.7
        var sfxVolume = 0.7
        var isMuted = false
        var hapticsEnabled = true
        var musicEnabled = true
    }

    private func makeModel(isMuted: Bool) -> AudioSettingsModel {
        let store = Store()
        store.isMuted = isMuted
        return AudioSettingsModel(
            player: nil,
            getMusicVolume: { store.musicVolume },
            setMusicVolume: { store.musicVolume = $0 },
            getSFXVolume: { store.sfxVolume },
            setSFXVolume: { store.sfxVolume = $0 },
            getIsMuted: { store.isMuted },
            setMuted: { store.isMuted = $0 },
            getHapticsEnabled: { store.hapticsEnabled },
            setHapticsEnabled: { store.hapticsEnabled = $0 },
            getMusicEnabled: { store.musicEnabled },
            setMusicEnabled: { store.musicEnabled = $0 }
        )
    }

    #if canImport(AppKit)
    /// Render the Sound section alone, mirroring the production composition
    /// in `SettingsScreen` (`AudioSettingsSection(model:tintColor:)`).
    @MainActor
    private func soundSection(model: AudioSettingsModel) -> some View {
        Form {
            AudioSettingsSection(model: model, tintColor: DefaultTheme().accent.primary.resolved)
        }
        .formStyle(.grouped)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotIPhoneLightUnmuted() {
        let model = makeModel(isMuted: false)
        let host = hostingView(
            soundSection(model: model),
            size: CGSize(width: 393, height: 420),
            colorScheme: .light
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "AudioSettingsSection-iPhone-light-unmuted")
        }
    }

    /// The bug-fix case: `musicEnabledRow` must render disabled (matching
    /// `musicVolumeRow`/`sfxVolumeRow`), while `hapticsRow` must render live
    /// (unlike the other three controls) — proving the two rows are no
    /// longer visually indistinguishable under master mute.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotIPhoneLightMuted() {
        let model = makeModel(isMuted: true)
        let host = hostingView(
            soundSection(model: model),
            size: CGSize(width: 393, height: 420),
            colorScheme: .light
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "AudioSettingsSection-iPhone-light-muted")
        }
    }
    #endif
}
