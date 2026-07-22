// Foundation tests (swift-testing-baseline). They assert the protocol-level
// contract: the Live player tolerates a missing asset key without crashing,
// playing an sfx event with a haptic fires the haptic, music does not start when
// other audio is playing (auto-yield), and the Noop impls are inert.
//
// All macOS-runnable: LiveSoundPlayer uses AVFoundation (present on macOS) and a
// bundle with no audio assets, so every play() hits the tolerated missing-asset
// path. The haptic seam is faked, so no UIKit dependency leaks into the test.

import Foundation
import Testing

@testable import GameAudio
import GameAudioTesting

@Suite("LiveSoundPlayer — missing-asset tolerance + haptic + auto-yield")
struct LiveSoundPlayerTests {

    /// A bundle with no audio assets (the test runner ships none), so every
    /// `soundKey` resolves to a missing asset — the normal P1 path.
    private func makePlayer(
        haptics: any HapticPlaying = NoopHapticPlaying(),
        session: any AudioSessionConfiguring = FakeAudioSession()
    ) -> LiveSoundPlayer {
        LiveSoundPlayer(
            bundle: .main,
            session: session,
            haptics: haptics,
            subsystem: "GameAudioTests"
        )
    }

    @Test("play() tolerates a missing asset key without crashing")
    func playMissingAssetIsNoop() {
        let player = makePlayer()
        // No asset for this key in the test bundle → logged + no-op, never traps.
        player.play(AudioEvent(soundKey: "does-not-exist"))
        player.play(AudioEvent(soundKey: "also-missing", channel: .sfx))
    }

    @Test("playMusic() tolerates a missing asset key without crashing")
    func playMusicMissingAssetIsNoop() {
        let player = makePlayer()
        player.playMusic(key: "missing-track")
        player.stopMusic()
    }

    @Test("playing an sfx event with a haptic fires the haptic")
    func sfxEventFiresHaptic() {
        let haptics = FakeHapticPlaying()
        let player = makePlayer(haptics: haptics)

        player.play(AudioEvent(soundKey: "tap", haptic: .light))

        // FakeHapticPlaying records synchronously — no drain needed.
        #expect(haptics.playedHaptics == [.light])
    }

    @Test("an sfx event with no haptic fires nothing")
    func sfxEventWithoutHapticFiresNothing() {
        let haptics = FakeHapticPlaying()
        let player = makePlayer(haptics: haptics)

        player.play(AudioEvent(soundKey: "tap"))

        #expect(haptics.playedHaptics.isEmpty)
    }

    // #939: `AudioEvent(soundKey: "")` is the deliberate "haptic-only, no
    // sound ever" contract (see `AudioEvent.soundKey` doc) — `play(_:)`
    // short-circuits BEFORE the bundle-resolve path for it, so a caller
    // firing this once per tap in a fast, repeated interaction never rescans
    // the bundle or logs a per-call "missing asset" notice the way an
    // ordinary unshipped `soundKey` would.
    //
    // The skip itself has no unit-testable public signal: `sfxPlayers` /
    // `resolveSFXPlayerLocked` are `private` (unreachable even via
    // `@testable import`, which only lifts `internal`), and `Bundle`'s
    // `url(forResource:withExtension:)` isn't interceptable without adding a
    // bundle-access seam — disproportionate for this one perf guard. What IS
    // testable, and regresses if the guard were ever hoisted ABOVE the haptic
    // dispatch instead of after it, is that the haptic still fires — this
    // locks that ordering.
    @Test("an empty-soundKey (haptic-only) event still fires its haptic")
    func emptySoundKeyEventStillFiresHaptic() {
        let haptics = FakeHapticPlaying()
        let player = makePlayer(haptics: haptics)

        player.play(AudioEvent(soundKey: "", haptic: .light))

        #expect(haptics.playedHaptics == [.light])
    }

    @Test("music does not start when other audio is playing (auto-yield)")
    func musicAutoYields() {
        let session = FakeAudioSession(isOtherAudioPlaying: true)
        let player = makePlayer(session: session)
        // Auto-yield returns before any asset lookup; the assertion is that it
        // does not trap and respects the session — no observable side effect to
        // probe on the Live player, so reaching here is the pass.
        player.playMusic(key: "missing-track")
    }

    @Test("volume / mute setters are tolerated and clamp out of range")
    func settersTolerated() {
        let player = makePlayer()
        player.setSFXVolume(2.0)   // clamps to 1
        player.setMusicVolume(-1)  // clamps to 0
        player.setMuted(true)
        player.setMuted(false)
        player.setMusicEnabled(false)
        player.setMusicEnabled(true)
    }
}

@Suite("Noop conformers are inert")
struct NoopAudioTests {

    @Test("NoopSoundPlaying does nothing")
    func noopSoundPlayer() {
        let player = NoopSoundPlaying()
        player.play(AudioEvent(soundKey: "x", haptic: .heavy))
        player.playMusic(key: "y")
        player.stopMusic()
        player.setSFXVolume(0.5)
        player.setMusicVolume(0.5)
        player.setMuted(true)
        player.setMusicEnabled(false)
    }

    @Test("NoopHapticPlaying does nothing")
    func noopHaptics() {
        NoopHapticPlaying().play(.success)
    }

    @Test("NoopAudioSession reports no other audio and configures inertly")
    func noopSession() {
        let session = NoopAudioSession()
        session.configureAmbient()
        #expect(session.isOtherAudioPlaying == false)
    }
}

@Suite("Fake conformers record calls")
struct FakeAudioTests {

    @Test("FakeSoundPlaying records events, music, volumes, and flags")
    func fakeRecords() {
        let fake = FakeSoundPlaying()

        fake.play(AudioEvent(soundKey: "a", haptic: .medium))
        fake.playMusic(key: "bgm")
        fake.stopMusic()
        fake.setSFXVolume(0.3)
        fake.setMusicVolume(0.6)
        fake.setMuted(true)
        fake.setMusicEnabled(false)
        fake.setHapticsEnabled(false)

        // Recording is synchronous — no drain needed.
        let events = fake.playedEvents
        #expect(events.map(\.soundKey) == ["a"])
        #expect(events.first?.haptic == .medium)

        #expect(fake.startedMusicKeys == ["bgm"])
        #expect(fake.stopMusicCount == 1)
        #expect(fake.sfxVolume == 0.3)
        #expect(fake.musicVolume == 0.6)
        #expect(fake.isMuted == true)
        #expect(fake.isMusicEnabled == false)
        #expect(fake.hapticsEnabled == false)
    }

    @Test("FakeSoundPlaying records play() calls in exact call order")
    func fakeRecordsEventsInOrder() {
        let fake = FakeSoundPlaying()
        let first = AudioEvent(soundKey: "A")
        let second = AudioEvent(soundKey: "B")

        fake.play(first)
        fake.play(second)

        // Synchronous recording guarantees order: [A, B], never [B, A].
        #expect(fake.playedEvents == [first, second])
    }

    @Test("FakeHapticPlaying records play() calls in exact call order")
    func fakeHapticsRecordInOrder() {
        let fake = FakeHapticPlaying()

        fake.play(.light)
        fake.play(.heavy)

        #expect(fake.playedHaptics == [.light, .heavy])
    }

    @Test("FakeAudioSession is scriptable")
    func fakeSessionScriptable() {
        let session = FakeAudioSession(isOtherAudioPlaying: true)
        #expect(session.isOtherAudioPlaying == true)
        session.configureAmbient()
        #expect(session.didConfigure == true)
        session.isOtherAudioPlaying = false
        #expect(session.isOtherAudioPlaying == false)
    }
}

@Suite("AudioEvent value type")
struct AudioEventTests {

    @Test("default init is sfx channel, no haptic")
    func defaults() {
        let event = AudioEvent(soundKey: "place")
        #expect(event.soundKey == "place")
        #expect(event.haptic == nil)
        #expect(event.channel == .sfx)
    }

    @Test("Hashable / Equatable")
    func hashable() {
        let lhs = AudioEvent(soundKey: "k", haptic: .light, channel: .sfx)
        let rhs = AudioEvent(soundKey: "k", haptic: .light, channel: .sfx)
        #expect(lhs == rhs)
        #expect(Set([lhs, rhs]).count == 1)
    }
}

// The two shared assets (#446 part-2) must be reachable via `Bundle.module`, or
// the `LiveSoundPlayer` fallback finds nothing and both apps go SILENTLY silent
// (no crash — audio can't be snapshot-tested). This proves they're bundled.
@Suite("GameAudioKit shared resources are bundled (#446)")
struct SharedAudioResourcesTests {

    @Test("gameplay.caf (shared BGM) resolves from Bundle.module")
    func gameplayBGMBundled() {
        #expect(SharedAudioResources.url(forResource: "gameplay", withExtension: "caf") != nil)
    }

    @Test("win.wav (shared SFX) resolves from Bundle.module")
    func winSFXBundled() {
        #expect(SharedAudioResources.url(forResource: "win", withExtension: "wav") != nil)
    }
}
