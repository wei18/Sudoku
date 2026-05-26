import Foundation
import Testing
@testable import GameCenterClient
import TelemetryTesting

@Suite("GameCenterClient — authentication")
struct GameCenterClientAuthTests {

    @Test func authenticatedStateSurfaced() async throws {
        let player = PlayerSummary(teamPlayerId: "PG1", displayName: "Wei")
        let driver = FakeAuthDriver(nextOutcome: .signedIn(player))
        let client = LiveGameCenterClient(authDriver: driver)
        let state = try await client.authenticate()
        #expect(state == .authenticated(player))
    }

    @Test func cancelledMapsToError() async throws {
        let driver = FakeAuthDriver(nextOutcome: .cancelled)
        let client = LiveGameCenterClient(authDriver: driver)
        await #expect(throws: GameCenterError.self) {
            _ = try await client.authenticate()
        }
    }

    @Test func restrictedMapsToRestricted() async throws {
        let driver = FakeAuthDriver(nextOutcome: .restricted)
        let client = LiveGameCenterClient(authDriver: driver)
        let state = try await client.authenticate()
        #expect(state == .restricted)
    }

    @Test func unavailableInRegionMapsToState() async throws {
        let driver = FakeAuthDriver(nextOutcome: .unavailableInRegion)
        let client = LiveGameCenterClient(authDriver: driver)
        let state = try await client.authenticate()
        #expect(state == .unavailableInRegion)
    }

    @Test func authStateUpdatesStreamsChanges() async throws {
        let player = PlayerSummary(teamPlayerId: "PG2", displayName: "Wei")
        let driver = FakeAuthDriver(nextOutcome: .signedIn(player))
        let client = LiveGameCenterClient(authDriver: driver)
        _ = try await client.authenticate()

        let stream = await client.authStateUpdates()
        var iterator = stream.makeAsyncIterator()
        // First emission is the cached state (already authenticated).
        let cached = await iterator.next()
        #expect(cached == .authenticated(player))

        // Push a sign-out through the driver; observer should forward it.
        await driver.emit(.signedOut)
        let next = await iterator.next()
        #expect(next == .unauthenticated)
    }
}
