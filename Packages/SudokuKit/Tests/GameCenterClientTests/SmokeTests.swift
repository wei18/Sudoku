import Testing
@testable import GameCenterClient

@Suite("GameCenterClient smoke")
struct GameCenterClientSmokeTests {
    @Test func packageCompiles() {
        _moduleAnchor()
    }
}
