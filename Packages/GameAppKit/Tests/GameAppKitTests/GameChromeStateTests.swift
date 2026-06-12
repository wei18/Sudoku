// GameChromeStateTests — SDD-003 OQ-001: modal top-chrome timer carrier.
//
// Verifies that `GameChromeState` correctly manages the elapsed label lifecycle:
//   - starts nil (board hasn't ticked yet)
//   - reflects the latest value passed to `updateElapsed(_:)`
//   - resets to nil when `reset()` is called (modal dismissed)

import Testing
@testable import GameAppKit

@MainActor
@Suite("GameChromeState — elapsed label lifecycle (SDD-003 OQ-001)")
struct GameChromeStateTests {

    @Test func initialLabelIsNil() {
        let sut = GameChromeState()
        #expect(sut.elapsedLabel == nil)
    }

    @Test func updateElapsedSetsLabel() {
        let sut = GameChromeState()
        sut.updateElapsed("1:23")
        #expect(sut.elapsedLabel == "1:23")
    }

    @Test func updateElapsedOverwritesPreviousLabel() {
        let sut = GameChromeState()
        sut.updateElapsed("0:05")
        sut.updateElapsed("0:06")
        #expect(sut.elapsedLabel == "0:06")
    }

    @Test func resetClearsLabel() {
        let sut = GameChromeState()
        sut.updateElapsed("3:45")
        sut.reset()
        #expect(sut.elapsedLabel == nil)
    }

    @Test func resetOnFreshInstanceIsNoop() {
        let sut = GameChromeState()
        // Must not crash and must stay nil.
        sut.reset()
        #expect(sut.elapsedLabel == nil)
    }
}
