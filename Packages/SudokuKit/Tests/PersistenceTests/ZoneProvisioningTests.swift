// ZoneProvisioningTests — §How.2 custom zone bring-up.

import Testing
import SudokuKitTesting
@testable import Persistence

@Suite("Persistence — zone provisioning")
struct ZoneProvisioningTests {

    @Test func provisionCreatesUserZoneOnce() async throws {
        let gateway = FakePrivateCKGateway()
        try await gateway.provisionZone()
        let ops = await gateway.operations
        #expect(ops == [.modifyRecordZones])
    }

    @Test func idempotentOnExistingZone() async throws {
        let gateway = FakePrivateCKGateway()
        try await gateway.provisionZone()
        try await gateway.provisionZone()
        try await gateway.provisionZone()
        let ops = await gateway.operations
        #expect(ops.filter { $0 == .modifyRecordZones }.count == 1)
    }

    @Test func zoneNameConstantMatchesDesign() {
        #expect(PrivateCKConstants.zoneName == "com.wei18.sudoku.userZone")
    }
}
