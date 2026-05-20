// Preview composition — fakes for SwiftUI #Preview.
//
// All factories return deterministic in-memory state. No CloudKit, no
// GameKit, no OSLog. Mirrors `.tests()` semantically; kept as a separate
// entry purely so future Preview-only tweaks (canned snapshots etc.) can
// land without affecting unit/snapshot test behavior.

internal import SudokuKitTesting
internal import SudokuUI

extension AppComposition {

    public static func preview() -> AppComposition {
        fakeComposition()
    }

    public static func tests() -> AppComposition {
        fakeComposition()
    }

    internal static func fakeComposition() -> AppComposition {
        let gameCenter = FakeGameCenterClient()
        let persistence = FakePersistence()

        let rootViewModel = RootViewModel(
            gameCenter: gameCenter,
            persistence: persistence
        )

        return AppComposition(
            rootViewModel: rootViewModel
        )
    }
}
