import Testing
@testable import Persistence

@Suite("Persistence smoke")
struct PersistenceSmokeTests {
    @Test func packageCompiles() {
        moduleAnchor()
    }
}
