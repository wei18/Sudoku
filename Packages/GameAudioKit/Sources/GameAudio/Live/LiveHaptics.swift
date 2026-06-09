// LiveHaptics — the production `HapticPlaying`, wrapping UIKit's feedback
// generators on iOS.
//
// RESTRICTED IMPORT: the only file allowed to import `UIKit`. macOS / other
// platforms have no `UIFeedbackGenerator`, so `play(_:)` is a no-op there (the
// package still builds + tests run via `swift test` on macOS).
//
// `@MainActor` hop: UIKit feedback generators must be used on the main thread.
// The protocol is nonisolated + `Sendable`, so we dispatch to `MainActor` for the
// actual generator call.

#if canImport(UIKit)
internal import UIKit
#endif

public struct LiveHaptics: HapticPlaying {

    public init() {}

    public func play(_ kind: HapticKind) {
        #if canImport(UIKit)
        Task { @MainActor in
            switch kind {
            case .light:
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            case .medium:
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case .heavy:
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            case .success:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .warning:
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            case .error:
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
        #endif
        // macOS / other: no UIKit haptics — no-op.
    }
}
