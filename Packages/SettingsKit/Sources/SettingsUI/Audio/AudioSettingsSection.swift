// AudioSettingsSection — the shared Settings audio entry (#330 P1).
//
// One `Section("Sound")` shared by BOTH apps (Minesweeper mirrors Sudoku), driven
// by the shared `AudioSettingsModel`. Mirrors `ReminderSettingsSection`'s styling
// (icon-leading rows, no `@Environment(\.theme)` dependency on the section itself
// — tint injected as `Color` so Minesweeper mounts the identical section).
//
// Controls:
//   - a master "Sound" mute toggle
//   - Music Volume `Slider`
//   - Sound-Effects Volume `Slider`
//   - a "Background Music" toggle
//   - a "Haptics" toggle
//
// Labels are `Text` literals resolved from each host app's own
// `Localizable.xcstrings` (Bundle.main), exactly like `SettingsScreen`'s own
// section titles — added to both shipping catalogs in all 7 locales (the
// scan:l10n gate).

public import SwiftUI

public struct AudioSettingsSection: View {
    @Bindable private var model: AudioSettingsModel
    private let tintColor: Color

    public init(model: AudioSettingsModel, tintColor: Color) {
        self.model = model
        self.tintColor = tintColor
    }

    public var body: some View {
        Section("Sound") {
            muteRow
            musicVolumeRow
            sfxVolumeRow
            musicEnabledRow
            hapticsRow
        }
    }

    // MARK: - Rows

    /// Master mute toggle. When on, all output is silenced (per-channel volumes
    /// are preserved). The toggle label spans the row as its tap target.
    private var muteRow: some View {
        Toggle(isOn: Binding(get: { !model.isMuted }, set: { model.isMuted = !$0 })) {
            Label {
                Text("Sound")
            } icon: {
                Image(systemName: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(tintColor)
            }
        }
        .tint(tintColor)
        .accessibilityIdentifier("audio.settings.mute")
    }

    /// Background-music channel volume.
    private var musicVolumeRow: some View {
        VStack(alignment: .leading) {
            Label {
                Text("Music Volume")
            } icon: {
                Image(systemName: "music.note")
                    .foregroundStyle(tintColor)
            }
            Slider(value: $model.musicVolume, in: 0...1)
                .tint(tintColor)
                .disabled(model.isMuted || !model.musicEnabled)
        }
        .accessibilityIdentifier("audio.settings.musicVolume")
    }

    /// Sound-effects channel volume.
    private var sfxVolumeRow: some View {
        VStack(alignment: .leading) {
            Label {
                Text("Sound Effects Volume")
            } icon: {
                Image(systemName: "waveform")
                    .foregroundStyle(tintColor)
            }
            Slider(value: $model.sfxVolume, in: 0...1)
                .tint(tintColor)
                .disabled(model.isMuted)
        }
        .accessibilityIdentifier("audio.settings.sfxVolume")
    }

    /// Background-music on/off toggle. Disabled while master-muted: `LiveSoundPlayer.
    /// playMusic` gates on `isMusicEnabled && !isMuted` (#330 P2), so flipping this
    /// toggle has zero audible effect until Sound is unmuted — same rule as
    /// `musicVolumeRow`'s `.disabled(isMuted...)` a few lines up. Without this, F-10
    /// (#879) reported the toggle looking "live" right next to a dimmed slider that
    /// says the opposite.
    private var musicEnabledRow: some View {
        Toggle(isOn: $model.musicEnabled) {
            Label {
                Text("Background Music")
            } icon: {
                Image(systemName: "music.quarternote.3")
                    .foregroundStyle(tintColor)
            }
        }
        .tint(tintColor)
        .disabled(model.isMuted)
        .accessibilityIdentifier("audio.settings.musicEnabled")
    }

    /// Haptic-feedback on/off toggle. Deliberately stays enabled under master mute:
    /// `LiveSoundPlayer.play` gates haptics on `hapticsEnabled` ONLY, independent of
    /// `isMuted` (#330 P2) — muting audio does not silence haptic feedback, so this
    /// toggle keeps having a real, immediate effect while Sound is off.
    private var hapticsRow: some View {
        Toggle(isOn: $model.hapticsEnabled) {
            Label {
                Text("Haptics")
            } icon: {
                Image(systemName: "hand.tap")
                    .foregroundStyle(tintColor)
            }
        }
        .tint(tintColor)
        .accessibilityIdentifier("audio.settings.haptics")
    }
}
