// AccountFlowTests — Phase 5.7: design.md §How.6.5 Case A / B / C.

import Foundation
import Testing
import SudokuKitTesting
@testable import Persistence

@Suite("Persistence — account flow (Case A/B/C)")
struct AccountFlowTests {

    @Test func caseANeverSignedIn() async throws {
        let provider = FakeAccountProvider(status: .noAccount, currentHash: nil)
        let keychain = FakeUserHashKeychain()
        let monitor = AccountMonitor(provider: provider, keychain: keychain)

        // CK guard throws iCloudNotSignedIn (everSignedIn=false).
        await #expect(throws: PersistenceError.iCloudNotSignedIn) {
            try await monitor.currentGuard(everSignedIn: false)
        }
        // Local cache still readable.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SudokuCache-caseA-\(UUID().uuidString)", isDirectory: true)
        let cache = LocalCache(baseURL: dir)
        try await cache.store(name: "starter.json", data: Data("ok".utf8))
        let loaded = try await cache.load(name: "starter.json")
        #expect(loaded == Data("ok".utf8))
        try? await cache.wipe()
    }

    @Test func caseBSignedOutDuringSession() async throws {
        let provider = FakeAccountProvider(status: .noAccount, currentHash: nil)
        let keychain = FakeUserHashKeychain(initial: "user-1-hash")
        let monitor = AccountMonitor(provider: provider, keychain: keychain)

        // Was authenticated (everSignedIn=true) → distinguishing error.
        await #expect(throws: PersistenceError.iCloudSignedOutDuringSession) {
            try await monitor.currentGuard(everSignedIn: true)
        }
        // handleAccountChange returns .signedOut and clears keychain.
        let outcome = try await monitor.handleAccountChange()
        #expect(outcome == .signedOut)
        let storedAfter = await keychain.stored
        #expect(storedAfter == nil)
    }

    @Test func caseCAccountChanged() async throws {
        let provider = FakeAccountProvider(status: .available, currentHash: "user-2-hash")
        let keychain = FakeUserHashKeychain(initial: "user-1-hash")
        let monitor = AccountMonitor(provider: provider, keychain: keychain)
        let outcome = try await monitor.handleAccountChange()
        switch outcome {
        case .switched(let oldHash, let newHash):
            #expect(oldHash == "user-1-hash")
            #expect(newHash == "user-2-hash")
        default:
            Issue.record("Expected .switched, got \(outcome)")
        }
        let storedAfter = await keychain.stored
        #expect(storedAfter == "user-2-hash")
    }

    @Test func keychainStoresUserRecordIDHash() async throws {
        let keychain = FakeUserHashKeychain()
        let provider = FakeAccountProvider(status: .available, currentHash: "user-X")
        let monitor1 = AccountMonitor(provider: provider, keychain: keychain)
        _ = try await monitor1.handleAccountChange()
        let storedAfterFirst = await keychain.stored
        #expect(storedAfterFirst == "user-X")
        // New monitor instance, same keychain → second observation is .unchanged.
        let monitor2 = AccountMonitor(provider: provider, keychain: keychain)
        let outcome = try await monitor2.handleAccountChange()
        #expect(outcome == .unchanged)
    }
}
