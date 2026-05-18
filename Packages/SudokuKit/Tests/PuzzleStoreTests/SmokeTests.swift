import Testing
@testable import PuzzleStore

@Suite("PuzzleStore smoke")
struct PuzzleStoreSmokeTests {
    @Test func packageCompiles() {
        moduleAnchor()
    }
}
