// LastSelectionStoreTests — UserDefaults round-trip coverage (#720).
// Each test injects an ephemeral suite (mirrors
// `MinesweeperWinCountStoreTests`' pattern) so runs never touch the real
// `UserDefaults.standard`.

import Foundation
import Testing
@testable import GameAppKit

@Suite("LastSelectionStore")
struct LastSelectionStoreTests {

    private func ephemeralDefaults() -> UserDefaults {
        // swiftlint:disable:next force_unwrapping
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    @Test("A fresh store returns the fallback (first-launch default)")
    func freshStoreReturnsFallback() {
        let store = LastSelectionStore(
            key: "com.wei18.test.practice.lastDifficulty",
            fallback: "medium",
            defaults: ephemeralDefaults()
        )
        #expect(store.load() == "medium")
    }

    @Test("save then load round-trips the persisted value (simulated relaunch)")
    func saveThenLoadRoundTrips() {
        let defaults = ephemeralDefaults()
        let store = LastSelectionStore(
            key: "com.wei18.test.practice.lastDifficulty",
            fallback: "medium",
            defaults: defaults
        )
        store.save("hard")

        // A brand-new `LastSelectionStore` reading the SAME UserDefaults suite
        // simulates a relaunch: no in-memory state survives, only what was
        // persisted.
        let reloaded = LastSelectionStore(
            key: "com.wei18.test.practice.lastDifficulty",
            fallback: "medium",
            defaults: defaults
        )
        #expect(reloaded.load() == "hard")
    }

    @Test("Two independent ephemeral suites never bleed into each other")
    func independentSuitesDoNotBleed() {
        let storeOne = LastSelectionStore(key: "k", fallback: "a", defaults: ephemeralDefaults())
        let storeTwo = LastSelectionStore(key: "k", fallback: "a", defaults: ephemeralDefaults())

        storeOne.save("b")

        #expect(storeOne.load() == "b")
        #expect(storeTwo.load() == "a")
    }
}
