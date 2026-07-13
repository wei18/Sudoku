// MinesweeperBoardViewTapModeTests — #720 G3: the board's Reveal/Flag
// tap-mode toggle must survive re-opening a board instead of always
// resetting to Reveal. `MinesweeperBoardView` has no SwiftUI render-tree
// introspection available in this repo's test infra (`AnyView`'s payload
// isn't introspectable per `LiveRouteFactoryTests`), so this suite drives the
// `internal` static seam (`tapModeKey` + `interactionMode(fromRawValue:)` /
// `rawValue(for:)`) directly against an ephemeral `LastSelectionStore`,
// mirroring the exact key + fallback production uses.

import Foundation
import Testing
@testable import MinesweeperUI
import GameAppKit

@MainActor
@Suite("MinesweeperBoardView — tap-mode persistence (#720 G3)")
struct MinesweeperBoardViewTapModeTests {

    private func ephemeralStore() -> LastSelectionStore {
        LastSelectionStore(
            key: MinesweeperBoardView.tapModeKey,
            fallback: "reveal",
            // swiftlint:disable:next force_unwrapping
            defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        )
    }

    @Test("A fresh store decodes to .reveal (first-open default, unchanged behavior)")
    func freshStoreDefaultsToReveal() {
        let store = ephemeralStore()
        #expect(MinesweeperBoardView.interactionMode(fromRawValue: store.load()) == .reveal)
    }

    @Test("save then load round-trips .flag (simulated relaunch)")
    func flagRoundTrips() {
        let store = ephemeralStore()
        store.save(MinesweeperBoardView.rawValue(for: .flag))

        #expect(MinesweeperBoardView.interactionMode(fromRawValue: store.load()) == .flag)
    }

    @Test("save then load round-trips .reveal explicitly")
    func revealRoundTrips() {
        let store = ephemeralStore()
        store.save(MinesweeperBoardView.rawValue(for: .flag))
        store.save(MinesweeperBoardView.rawValue(for: .reveal))

        #expect(MinesweeperBoardView.interactionMode(fromRawValue: store.load()) == .reveal)
    }

    @Test("An unrecognized stored raw value falls back to .reveal defensively")
    func unrecognizedRawValueFallsBackToReveal() {
        #expect(MinesweeperBoardView.interactionMode(fromRawValue: "garbage") == .reveal)
    }

    // MARK: - #796 regression: injected store is actually live

    /// #796: `MinesweeperBoardView` used to seed `interactionMode` from
    /// `UserDefaults.standard` unconditionally, so the swiftpm test host's
    /// shared persistent domain could silently flip a snapshot recording to
    /// Flag mode. This poisons an ISOLATED store (never touching `.standard`)
    /// with `tapMode = flag` and constructs the real view through the
    /// `tapModeDefaults:` seam, proving the injection actually feeds
    /// `interactionMode` — not just the static round-trip helpers above.
    @Test("a poisoned isolated store seeds interactionMode = .flag, proving the injection is live")
    func poisonedIsolatedStoreSeedsFlagMode() {
        let suiteName = "test.poison.\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        let poisoned = UserDefaults(suiteName: suiteName)!
        poisoned.set("flag", forKey: MinesweeperBoardView.tapModeKey)
        defer { poisoned.removePersistentDomain(forName: suiteName) }

        let boardView = MinesweeperBoardView(difficulty: .beginner, seed: 42, tapModeDefaults: poisoned)

        #expect(boardView.interactionMode == .flag)
    }

    /// Same poison, via the `viewModel:` init overload (the one every
    /// seeded-snapshot suite uses) — both `init`s must honor the seam
    /// identically.
    @Test("a poisoned isolated store seeds interactionMode = .flag via the viewModel: init too")
    func poisonedIsolatedStoreSeedsFlagModeViaViewModelInit() {
        let suiteName = "test.poison.\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        let poisoned = UserDefaults(suiteName: suiteName)!
        poisoned.set("flag", forKey: MinesweeperBoardView.tapModeKey)
        defer { poisoned.removePersistentDomain(forName: suiteName) }

        let boardView = MinesweeperBoardView(
            viewModel: MinesweeperGameViewModel(difficulty: .beginner, seed: 42),
            suppressTickerForSnapshot: true,
            tapModeDefaults: poisoned
        )

        #expect(boardView.interactionMode == .flag)
    }
}
