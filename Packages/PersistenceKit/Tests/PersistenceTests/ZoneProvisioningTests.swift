// ZoneProvisioningTests — §How.2 custom zone bring-up.

import Testing
import PersistenceTesting
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

    @Test func sudokuConfigMatchesDesign() {
        #expect(PrivateCKConfig.sudoku.zoneName == "com.wei18.sudoku.userZone")
        #expect(PrivateCKConfig.sudoku.subscriptionID == "com.wei18.sudoku.userZone.changes")
    }

    @Test func minesweeperConfigUsesDistinctNamespace() {
        #expect(PrivateCKConfig.minesweeper.zoneName == "com.wei18.minesweeper.userZone")
        #expect(PrivateCKConfig.minesweeper.subscriptionID == "com.wei18.minesweeper.userZone.changes")
        // No namespace collision with Sudoku — each app owns its own.
        #expect(PrivateCKConfig.minesweeper.zoneName != PrivateCKConfig.sudoku.zoneName)
        #expect(PrivateCKConfig.minesweeper.subscriptionID != PrivateCKConfig.sudoku.subscriptionID)
    }
}
