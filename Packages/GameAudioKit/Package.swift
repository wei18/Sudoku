// swift-tools-version: 6.2

import PackageDescription

// MARK: - Shared settings (foundations.md §1: Swift 6 + complete concurrency)

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

// MARK: - Production targets
//
// GameAudioKit is a leaf sibling local package: the shared game-audio mechanism
// consumed by both Sudoku and Minesweeper (issue #330 Phase 1). It mirrors
// RemindersKit's protocol-seam shape exactly — public protocols + value types in
// `GameAudio`, the `AVFoundation` / `AVAudioSession` / `UIKit` conformers under
// `GameAudio/Live`, Noop conformers for previews / audio-disabled, and shared
// `GameAudioTesting` fakes.
//
// Game-agnostic by construction: `AudioEvent` carries a string `soundKey`
// (mapping to an asset filename later), an optional haptic, and a channel. No
// Sudoku/Minesweeper event names live here — those constants are P2, defined by
// the apps.
//
// Restricted-import rule (swiftpm-modularization): `AVFoundation`,
// `AVFAudio` (AVAudioSession), and `UIKit` are imported ONLY in the
// `GameAudio/Live` files. The protocol / value-type layer (and every consumer)
// sees only the seams — same discipline as UserNotifications→Reminders/Live.
//
// Dep direction: GameAudioKit is a leaf — no in-house deps. SettingsKit depends
// ON `GameAudio` (one-way); `GameAudio` does NOT import SettingsKit, so there is
// no cycle.

let package = Package(
    name: "GameAudioKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "GameAudio", targets: ["GameAudio"]),
        .library(name: "GameAudioTesting", targets: ["GameAudioTesting"]),
    ],
    targets: [
        .target(
            name: "GameAudio",
            swiftSettings: swiftSettings
        ),
        // GameAudioTesting — shared fakes (FakeSoundPlaying + FakeHapticPlaying +
        // FakeAudioSession). Records calls + holds scriptable state so any consumer
        // (GameAudioTests + app composition tests) can assert call shape without
        // touching AVFoundation or the system audio session.
        .target(
            name: "GameAudioTesting",
            dependencies: [
                "GameAudio",
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "GameAudioTests",
            dependencies: [
                "GameAudio",
                "GameAudioTesting",
            ],
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
