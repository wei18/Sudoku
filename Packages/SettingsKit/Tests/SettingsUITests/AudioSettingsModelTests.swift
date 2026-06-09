// AudioSettingsModelTests (#330 P1). Assert the model seeds from injected
// persistence on init (without re-persisting), and that each setter both persists
// via the injected closure AND pushes the new value to the injected live player.

import Foundation
import Testing

import GameAudio
import GameAudioTesting
@testable import SettingsUI

@MainActor
@Suite("AudioSettingsModel — persistence + live-player push")
struct AudioSettingsModelTests {

    /// A mutable backing store for the injected get/set closures.
    final class Store {
        var musicVolume = 0.7
        var sfxVolume = 0.7
        var isMuted = false
        var hapticsEnabled = true
        var musicEnabled = true
    }

    private func makeModel(
        store: Store,
        player: (any SoundPlaying)? = nil
    ) -> AudioSettingsModel {
        AudioSettingsModel(
            player: player,
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

    @Test("seeds in-memory state from persistence without re-persisting")
    func seedsFromPersistence() {
        let store = Store()
        store.musicVolume = 0.4
        store.sfxVolume = 0.9
        store.isMuted = true
        store.hapticsEnabled = false
        store.musicEnabled = false

        let model = makeModel(store: store)

        #expect(model.musicVolume == 0.4)
        #expect(model.sfxVolume == 0.9)
        #expect(model.isMuted == true)
        #expect(model.hapticsEnabled == false)
        #expect(model.musicEnabled == false)
    }

    @Test("default-on BGM + haptics + not-muted + 0.7 volumes flow through")
    func defaults() {
        let store = Store() // defaults: 0.7 / 0.7 / false / true / true
        let model = makeModel(store: store)
        #expect(model.musicVolume == 0.7)
        #expect(model.sfxVolume == 0.7)
        #expect(model.isMuted == false)
        #expect(model.hapticsEnabled == true)
        #expect(model.musicEnabled == true)
    }

    @Test("setters persist via the injected closures")
    func settersPersist() {
        let store = Store()
        let model = makeModel(store: store)

        model.musicVolume = 0.2
        model.sfxVolume = 0.3
        model.isMuted = true
        model.hapticsEnabled = false
        model.musicEnabled = false

        #expect(store.musicVolume == 0.2)
        #expect(store.sfxVolume == 0.3)
        #expect(store.isMuted == true)
        #expect(store.hapticsEnabled == false)
        #expect(store.musicEnabled == false)
    }

    @Test("setters push to the injected live player")
    func settersPushToPlayer() async {
        let store = Store()
        let player = FakeSoundPlaying()
        let model = makeModel(store: store, player: player)

        model.musicVolume = 0.25
        model.sfxVolume = 0.35
        model.isMuted = true
        model.musicEnabled = false

        // FakeSoundPlaying records via detached Tasks; let them drain.
        try? await Task.sleep(for: .milliseconds(50))

        #expect(await player.musicVolume == Float(0.25))
        #expect(await player.sfxVolume == Float(0.35))
        #expect(await player.isMuted == true)
        #expect(await player.isMusicEnabled == false)
    }

    @Test("nil player is tolerated (Previews / audio-disabled)")
    func nilPlayerTolerated() {
        let store = Store()
        let model = makeModel(store: store, player: nil)
        model.musicVolume = 0.1 // must not trap
        #expect(store.musicVolume == 0.1)
    }
}
