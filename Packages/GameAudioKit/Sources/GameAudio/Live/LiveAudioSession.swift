// LiveAudioSession — the production `AudioSessionConfiguring`, wrapping
// `AVAudioSession` on iOS.
//
// RESTRICTED IMPORT: one of the only files allowed to import `AVFAudio`
// (AVAudioSession). The seam keeps every UI / logic / test layer free of the
// framework — same discipline as UserNotifications→Reminders/Live.
//
// Ambient + mixWithOthers (#330 P1): game audio is non-essential background
// sound, so we use `.ambient` (respects the silent switch, does NOT interrupt
// other audio) with `.mixWithOthers` (plays alongside the user's music/podcast).
// `isOtherAudioPlaying` lets the sound player auto-yield music when something
// else is already playing.
//
// macOS has no `AVAudioSession`, so `configureAmbient()` is a no-op and
// `isOtherAudioPlaying` is always `false` — this lets the package build + tests
// run via `swift test` on macOS.

internal import os

#if os(iOS)
internal import AVFAudio
#endif

public struct LiveAudioSession: AudioSessionConfiguring {

    private let logger: Logger

    /// - Parameter subsystem: OSLog subsystem — pass the host app's bundle id
    ///   (oslog-logger-defaults).
    public init(subsystem: String) {
        self.logger = Logger(subsystem: subsystem, category: "GameAudio")
    }

    public func configureAmbient() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true)
            logger.debug("configured ambient audio session (mixWithOthers)")
        } catch {
            logger.error("audio session configure failed: \(error.localizedDescription, privacy: .public)")
        }
        #endif
        // macOS / other: no AVAudioSession — nothing to configure.
    }

    public var isOtherAudioPlaying: Bool {
        #if os(iOS)
        AVAudioSession.sharedInstance().isOtherAudioPlaying
        #else
        false
        #endif
    }
}
