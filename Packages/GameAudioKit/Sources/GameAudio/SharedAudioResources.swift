// Shared audio resources (#446 part-2).
//
// The two byte-identical assets used by BOTH Sudoku and Minesweeper — the
// `gameplay.caf` BGM and `win.wav` — are vended once from GameAudioKit instead
// of being duplicated in each app bundle. `Package.swift` declares them as
// `.copy` resources on the `GameAudio` target, which synthesizes `Bundle.module`.
//
// `Bundle.module` is internal to this target, so `LiveSoundPlayer`'s resolution
// fallback reaches it directly. This enum exposes the same lookup internally so a
// `@testable` resource test can prove the assets are actually bundled — audio
// can't be snapshot-tested and a missing-resource wiring mistake is a SILENT
// no-sound, not a crash, so this test is the guardrail.

internal import Foundation

enum SharedAudioResources {
    /// Resolve a shared asset by `key` + `ext` from GameAudioKit's own resource
    /// bundle (`Bundle.module`). `nil` when not bundled.
    static func url(forResource key: String, withExtension ext: String) -> URL? {
        Bundle.module.url(forResource: key, withExtension: ext)
    }
}
