// MonetizationStateStoreTests — Phase v2.3.1: round-trip AdGateState through
// FakePrivateCKGateway. Live CloudKit verification deferred to v2.5.

import Foundation
import Testing
import MonetizationCore
import SudokuKitTesting
@testable import Persistence

@Suite("Persistence — MonetizationStateStore")
struct MonetizationStateStoreTests {

    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
    private var fixedClock: @Sendable () -> Date {
        let captured = fixedNow
        return { captured }
    }

    private func makeStore() -> (LiveMonetizationStateStore, FakePrivateCKGateway) {
        let gateway = FakePrivateCKGateway()
        let store = LiveMonetizationStateStore(gateway: gateway, clock: fixedClock)
        return (store, gateway)
    }

    // MARK: - First-launch seeding

    @Test func loadWithNoRecordSeedsFirstLaunchAtAndPersists() async throws {
        let (store, gateway) = makeStore()
        let state = try await store.loadState()
        #expect(state.firstLaunchAt == fixedNow)
        #expect(state.lastShownDate == nil)
        #expect(state.dismissedDate == nil)
        #expect(state.hasPurchasedRemoveAds == false)

        // Seed must be written through to the gateway so later launches see it.
        let recordCount = await gateway.recordCount()
        #expect(recordCount == 1)
    }

    @Test func secondLoadReturnsTheSameSeedNotANewOne() async throws {
        let (store, _) = makeStore()
        let first = try await store.loadState()
        let second = try await store.loadState()
        #expect(first.firstLaunchAt == second.firstLaunchAt)
    }

    // MARK: - Round-trip

    @Test func saveThenLoadRoundTripsAllFields() async throws {
        let (store, _) = makeStore()
        let written = AdGateState(
            firstLaunchAt: Date(timeIntervalSince1970: 1_000),
            lastShownDate: Date(timeIntervalSince1970: 2_000),
            dismissedDate: Date(timeIntervalSince1970: 3_000),
            hasPurchasedRemoveAds: true
        )
        try await store.saveState(written)
        let read = try await store.loadState()
        #expect(read == written)
    }

    @Test func nilOptionalsRoundTripAsNil() async throws {
        let (store, _) = makeStore()
        let written = AdGateState(
            firstLaunchAt: Date(timeIntervalSince1970: 1_000),
            lastShownDate: nil,
            dismissedDate: nil,
            hasPurchasedRemoveAds: false
        )
        try await store.saveState(written)
        let read = try await store.loadState()
        #expect(read.lastShownDate == nil)
        #expect(read.dismissedDate == nil)
        #expect(read.hasPurchasedRemoveAds == false)
    }

    @Test func hasPurchasedRemoveAdsTrueRoundTrips() async throws {
        let (store, _) = makeStore()
        var state = try await store.loadState()
        state.hasPurchasedRemoveAds = true
        try await store.saveState(state)
        let reloaded = try await store.loadState()
        #expect(reloaded.hasPurchasedRemoveAds == true)
    }

    // MARK: - Record shape

    @Test func payloadUsesMonetizationStateRecordTypeAndSingletonName() async throws {
        let (store, gateway) = makeStore()
        _ = try await store.loadState() // forces seed write
        let saved = try await gateway.fetch(recordName: "monetization-state")
        #expect(saved != nil)
        #expect(saved?.recordType == "MonetizationState")
        #expect(saved?.recordName == "monetization-state")
    }

    @Test func purchasedFlagIsEncodedAsInt() async throws {
        let (store, gateway) = makeStore()
        var state = try await store.loadState()
        state.hasPurchasedRemoveAds = true
        try await store.saveState(state)
        let saved = try await gateway.fetch(recordName: "monetization-state")
        guard case .int(let raw) = saved?.fields["hasPurchasedRemoveAds"] else {
            Issue.record("hasPurchasedRemoveAds should encode as RecordValue.int")
            return
        }
        #expect(raw == 1)
    }

    // MARK: - Codable round-trip on AdGateState (sanity)

    @Test func adGateStateCodableRoundTrip() throws {
        let state = AdGateState(
            firstLaunchAt: Date(timeIntervalSince1970: 4_000),
            lastShownDate: Date(timeIntervalSince1970: 5_000),
            dismissedDate: Date(timeIntervalSince1970: 6_000),
            hasPurchasedRemoveAds: true
        )
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(AdGateState.self, from: encoded)
        #expect(decoded == state)
    }
}
