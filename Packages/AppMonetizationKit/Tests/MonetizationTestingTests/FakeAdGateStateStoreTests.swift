import Foundation
import Testing
import MonetizationCore
@testable import MonetizationTesting

@Suite("FakeAdGateStateStore — round-trip")
struct FakeAdGateStateStoreTests {

    private static let seed = AdGateState(
        firstLaunchAt: Date(timeIntervalSince1970: 1_800_000_000),
        lastShownDate: nil,
        dismissedDate: nil,
        hasPurchasedRemoveAds: false
    )

    @Test func loadWithoutSeedThrows() async {
        let store = FakeAdGateStateStore()
        await #expect(throws: FakeAdGateStateStoreError.self) {
            _ = try await store.loadState()
        }
    }

    @Test func scriptThenLoadRoundTrips() async throws {
        let store = FakeAdGateStateStore()
        await store.script(Self.seed)
        let loaded = try await store.loadState()
        #expect(loaded == Self.seed)
        #expect(await store.loadCallCount == 1)
    }

    @Test func saveOverwritesAndCounts() async throws {
        let store = FakeAdGateStateStore(initial: Self.seed)
        var mutated = Self.seed
        mutated.hasPurchasedRemoveAds = true
        try await store.saveState(mutated)
        let loaded = try await store.loadState()
        #expect(loaded.hasPurchasedRemoveAds == true)
        #expect(await store.saveCallCount == 1)
        #expect(await store.loadCallCount == 1)
    }

    @Test func codableRoundTripPreservesState() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(Self.seed)
        let decoded = try decoder.decode(AdGateState.self, from: data)
        #expect(decoded == Self.seed)
    }
}
