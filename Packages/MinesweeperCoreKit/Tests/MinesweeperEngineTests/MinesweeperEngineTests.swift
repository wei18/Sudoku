import Testing
@testable import MinesweeperEngine

@Suite("MinesweeperEngine — skeleton smoke")
struct MinesweeperEngineTests {
    @Test func engineInstantiates() {
        _ = MinesweeperEngine()
    }
}
