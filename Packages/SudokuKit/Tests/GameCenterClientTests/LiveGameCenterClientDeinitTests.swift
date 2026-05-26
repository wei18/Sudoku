// LiveGameCenterClientDeinitTests — Wave-2 BLOCKER B3 regression.
//
// Pre-fix bug: `startObservingIfNeeded()` spawned
//   `Task { [authDriver] in for await ... { self.handleObservedOutcome(...) } }`
// — strong `self` capture + missing `await` on the actor-isolated hop.
// The for-await loop runs forever as long as the AuthDriver stream stays
// open, so `LiveGameCenterClient` could never deinit → permanent retain
// cycle.
//
// Post-fix: `[weak self, authDriver]` + `await self?.handle...`. Once the
// only owner releases the client, weak-self goes nil; the next stream
// event (or stream termination) lets the Task exit and deinit can fire.
//
// Per impl-notes meetings/2026-05-20_wave-2-blocker-fixes.impl-notes.md §B3.

import Foundation
import Testing
@testable import GameCenterClient
import TelemetryTesting

@Suite("GameCenterClient — LiveGameCenterClient deinit (B3)")
struct LiveGameCenterClientDeinitTests {

    @Test("Releasing the client clears the weak reference (no retain cycle)")
    func releasingClientNilsWeakReference() async throws {
        // Hold the client strongly only during authentication, then release
        // it and verify that a weak reference to it transitions to nil.
        let driver = FakeAuthDriver(nextOutcome: .signedIn(
            PlayerSummary(teamPlayerId: "PG-DEINIT", displayName: "Tester")
        ))

        weak var weakClient: LiveGameCenterClient?
        do {
            let client = LiveGameCenterClient(authDriver: driver)
            weakClient = client
            // Trigger startObservingIfNeeded() via authenticate().
            _ = try await client.authenticate()
            // Subscribe so the observer Task actually starts.
            _ = await client.authStateUpdates()
        }

        // Give the Task scheduler a few hops to run any pending cleanup.
        // The observer Task itself may still be alive (parked on
        // for-await), but it now only holds a WEAK reference to `self`,
        // so `weakClient` MUST be nil. Pre-fix, the strong-self capture
        // kept the client alive here.
        for _ in 0..<10 {
            await Task.yield()
        }

        #expect(weakClient == nil, "weak ref must be nil — no retain cycle")
    }
}
