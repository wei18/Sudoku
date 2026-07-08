// MinesweeperWinCountStoreTests — UserDefaults round-trip coverage (#700).
// Each test injects an ephemeral suite (mirrors ReminderPrimerCoordinatorTests'
// pattern) so runs never touch the real `UserDefaults.standard`.

import Foundation
import Testing
@testable import MinesweeperUI

@Suite("MinesweeperWinCountStore")
struct MinesweeperWinCountStoreTests {

    private func ephemeralStore() -> MinesweeperWinCountStore {
        // swiftlint:disable:next force_unwrapping
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        return MinesweeperWinCountStore(defaults: defaults)
    }

    @Test("A fresh store starts at 0")
    func freshStoreStartsAtZero() {
        #expect(ephemeralStore().currentCount == 0)
    }

    @Test("incrementAndGet returns the running total, INCLUDING this call")
    func incrementReturnsRunningTotal() {
        let store = ephemeralStore()
        #expect(store.incrementAndGet() == 1)
        #expect(store.incrementAndGet() == 2)
        #expect(store.incrementAndGet() == 3)
        #expect(store.currentCount == 3)
    }

    @Test("Two independent ephemeral suites never bleed into each other")
    func independentSuitesDoNotBleed() {
        let storeOne = ephemeralStore()
        let storeTwo = ephemeralStore()
        _ = storeOne.incrementAndGet()
        _ = storeOne.incrementAndGet()
        #expect(storeOne.currentCount == 2)
        #expect(storeTwo.currentCount == 0)
    }
}
