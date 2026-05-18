import Testing
@testable import GameState

@Suite("GameState smoke")
struct GameStateSmokeTests {
    @Test func packageCompiles() {
        _moduleAnchor()
    }
}
