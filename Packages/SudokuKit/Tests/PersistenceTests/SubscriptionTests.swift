// SubscriptionTests — §How.2 single CKDatabaseSubscription installer.

import Testing
import SudokuKitTesting
@testable import Persistence

@Suite("Persistence — subscription installer")
struct SubscriptionTests {

    @Test func subscriptionCreatedOnFirstLaunch() async throws {
        let gateway = FakePrivateCKGateway()
        let installer = SubscriptionInstaller(gateway: gateway)
        try await installer.installIfNeeded()
        let ops = await gateway.operations
        #expect(ops.filter { $0 == .modifySubscriptions }.count == 1)
    }

    @Test func idempotentOnRelaunch() async throws {
        let gateway = FakePrivateCKGateway()
        let installer = SubscriptionInstaller(gateway: gateway)
        try await installer.installIfNeeded()
        try await installer.installIfNeeded()
        try await installer.installIfNeeded()
        let ops = await gateway.operations
        #expect(ops.filter { $0 == .modifySubscriptions }.count == 1)
    }

    @Test func subscriptionIDMatchesDesign() {
        #expect(PrivateCKConstants.subscriptionID == "com.wei18.sudoku.userZone.changes")
    }
}
