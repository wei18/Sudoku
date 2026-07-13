// GKAuthDriverTimeoutTests — issue #766.
//
// `GKAuthDriver.performAuthentication()` used to `withCheckedContinuation`
// forever if GameKit's `authenticateHandler` callback never fired. These
// tests exercise the real `GKAuthDriver` (not `FakeAuthDriver`) because the
// timeout race lives inside the driver's own actor state machine.
//
// IMPORTANT: every test below calls `suppressGameKitInstallForTesting()`
// before touching the driver. Actually assigning
// `GKLocalPlayer.local.authenticateHandler` hangs the MainActor SYNCHRONOUSLY
// and INDEFINITELY in this unentitled SwiftPM test runner (no app bundle, no
// Game Center entitlement) — confirmed by a hung `swift test` run during
// development of this fix (killed after ~12 minutes at ~0% CPU, i.e. blocked
// in a syscall, not spinning). That is the same class of landmine as
// `CKContainer.default()` (see CLAUDE.md). `suppressGameKitInstallForTesting()`
// pre-marks the handler as installed so `installHandlerIfNeeded()` becomes a
// no-op and real GameKit is never touched — which conveniently also gives us
// a deterministic, non-flaky "callback never fires" scenario for the
// acceptance-criterion test, since nothing but our own timeout task will
// ever call `deliverOutcome(_:)`.
//
// For "callback fires" / "callback fires late", nothing in this process can
// make a real GameKit callback fire on demand anyway, so those two scenarios
// drive the actor directly through `deliverOutcome(_:)` — internal (not
// private) specifically so `@testable import` can reach it as a seam that
// simulates a genuine GameKit callback landing at a chosen instant.

import Foundation
import Testing
@testable import GameCenterClient
import Telemetry

@Suite("GKAuthDriver — handshake timeout (#766)")
struct GKAuthDriverTimeoutTests {

    /// Acceptance criterion: a callback that never fires must not hang
    /// `performAuthentication()` past the injected timeout.
    @Test func callbackNeverFiresDegradesWithinTimeout() async throws {
        let reporter = FakeErrorReporter()
        let driver = GKAuthDriver(handshakeTimeout: .milliseconds(50), errorReporter: reporter)
        await driver.suppressGameKitInstallForTesting()

        let clock = ContinuousClock()
        let start = clock.now
        let outcome = await driver.performAuthentication()
        let elapsed = clock.now - start

        #expect(outcome == .signedOut)
        #expect(elapsed < .seconds(2), "performAuthentication() should degrade near the timeout, not hang")

        let reports = await reporter.received
        #expect(reports.count == 1)
        #expect(reports.first?.source == "GKAuthDriver.handshakeTimeout")
        #expect(reports.first?.error == .gameCenterUnauthenticated)
    }

    /// Happy path: a callback landing before the deadline resolves normally
    /// and cancels the pending timeout work (no stray resume, no late
    /// timeout report).
    @Test func callbackFiresPromptlyResolvesNormallyAndCancelsTimeout() async throws {
        let reporter = FakeErrorReporter()
        let driver = GKAuthDriver(handshakeTimeout: .milliseconds(200), errorReporter: reporter)
        await driver.suppressGameKitInstallForTesting()
        let player = PlayerSummary(teamPlayerId: "PG1", displayName: "Wei")

        async let outcome = driver.performAuthentication()
        // Give performAuthentication() a moment to install pendingHandshake,
        // then simulate a genuine GameKit callback landing well before the
        // 200ms deadline.
        try await Task.sleep(for: .milliseconds(10))
        await driver.deliverOutcome(.signedIn(player))

        let resolved = await outcome
        #expect(resolved == .signedIn(player))

        // Wait past the original deadline; the timeout task must have been
        // cancelled by the prompt callback, so no timeout report should
        // ever land.
        try await Task.sleep(for: .milliseconds(250))
        let reports = await reporter.received
        #expect(reports.isEmpty, "a prompt callback must cancel the pending timeout")
    }

    /// A genuine callback that lands *after* the timeout already resolved
    /// `performAuthentication()` must not crash (no double-resume) and must
    /// still flow to the observer stream so downstream consumers recover.
    @Test func lateCallbackAfterTimeoutDoesNotCrashAndStillReachesObservers() async throws {
        let reporter = FakeErrorReporter()
        let driver = GKAuthDriver(handshakeTimeout: .milliseconds(30), errorReporter: reporter)
        await driver.suppressGameKitInstallForTesting()
        let player = PlayerSummary(teamPlayerId: "PG2", displayName: "Late")

        // Subscribe before the late callback so the stream can observe it.
        let stream = await driver.observeStateChanges()
        var iterator = stream.makeAsyncIterator()

        let outcome = await driver.performAuthentication()
        #expect(outcome == .signedOut, "timeout should have resolved performAuthentication() first")

        // The timeout's own resolution yields to observers too — consume
        // that event first (it was subscribed before the timeout fired).
        let timeoutObserved = await iterator.next()
        #expect(timeoutObserved == .signedOut)

        // Simulate the real GameKit callback finally landing late.
        await driver.deliverOutcome(.signedIn(player))

        let observed = await iterator.next()
        #expect(observed == .signedIn(player), "late callback must still flow to observers")

        // Only one timeout report — the late callback must not produce a
        // second one (it goes through deliverOutcome, not the timeout path).
        let reports = await reporter.received
        #expect(reports.count == 1)
        #expect(reports.first?.source == "GKAuthDriver.handshakeTimeout")
    }

    /// CR finding 1 (#766): `resolveHandshakeTimeout()` suspends across the
    /// cross-actor `await errorReporter.report(...)`. A genuine callback
    /// that runs `deliverOutcome(realOutcome)` during that suspension must
    /// win — the timeout path must re-check the latch after the await and
    /// NOT clobber `cachedOutcome`/observers back to `.signedOut`.
    @Test func callbackDuringTimeoutReportDoesNotGetClobbered() async throws {
        let reporter = GateErrorReporter()
        let driver = GKAuthDriver(handshakeTimeout: .milliseconds(20), errorReporter: reporter)
        await driver.suppressGameKitInstallForTesting()
        let player = PlayerSummary(teamPlayerId: "PG3", displayName: "RaceWinner")

        let stream = await driver.observeStateChanges()
        var iterator = stream.makeAsyncIterator()

        // Park a caller; the timeout fires at ~20ms and suspends inside
        // the gated reporter's report().
        async let parked = driver.performAuthentication()
        await reporter.waitUntilEntered()

        // While the timeout's report() is parked, the genuine GameKit
        // callback lands with the real outcome.
        await driver.deliverOutcome(.signedIn(player))
        let resolved = await parked
        #expect(resolved == .signedIn(player), "the genuine callback should resolve the parked caller")

        // Release the timeout's report(); its post-await latch re-check
        // must see didResolveHandshake == true and deliver nothing.
        await reporter.releaseGate()
        // Give the released timeout continuation time to hop back onto the
        // driver actor — so if a regression ever removes the re-check, its
        // stale .signedOut lands BEFORE the assertions below (not after).
        try await Task.sleep(for: .milliseconds(50))

        // cachedOutcome must retain the REAL outcome — a fresh
        // performAuthentication() short-circuits to currentOutcome().
        let cached = await driver.performAuthentication()
        #expect(cached == .signedIn(player), "cachedOutcome must not be clobbered back to .signedOut")

        // Observer stream: the genuine outcome, then NOTHING from the
        // released timeout. Deliver a marker and assert it is the very
        // next event (i.e. no stale .signedOut was interleaved).
        let first = await iterator.next()
        #expect(first == .signedIn(player))
        await driver.deliverOutcome(.cancelled)
        let second = await iterator.next()
        #expect(second == .cancelled, "no stale .signedOut may be re-yielded by the released timeout")
    }

    /// CR finding 2 (#766): two concurrent performAuthentication() callers
    /// on the same driver must BOTH park (multi-slot) and BOTH resolve
    /// within the timeout window when the callback never fires — a
    /// single-slot store would orphan (hang) the first caller forever.
    @Test func twoConcurrentCallersBothResolveWithinTimeout() async throws {
        let reporter = FakeErrorReporter()
        let driver = GKAuthDriver(handshakeTimeout: .milliseconds(50), errorReporter: reporter)
        await driver.suppressGameKitInstallForTesting()

        let clock = ContinuousClock()
        let start = clock.now
        async let first = driver.performAuthentication()
        async let second = driver.performAuthentication()
        let outcomes = await [first, second]
        let elapsed = clock.now - start

        #expect(outcomes == [.signedOut, .signedOut])
        #expect(elapsed < .seconds(2), "both concurrent callers must degrade near the timeout, not hang")

        // One timeout covers the parked cohort — exactly one report.
        let reports = await reporter.received
        #expect(reports.count == 1)
        #expect(reports.first?.source == "GKAuthDriver.handshakeTimeout")
    }
}

/// ErrorReporter whose `report()` suspends until the test releases it —
/// lets a test interleave a genuine callback INSIDE the timeout path's
/// cross-actor report suspension (CR finding 1 on #766).
private actor GateErrorReporter: ErrorReporter {
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var gateWaiter: CheckedContinuation<Void, Never>?
    private var hasEntered = false
    private var isReleased = false

    func report(_ error: UserFacingError, underlying: any Error, source: String) async {
        hasEntered = true
        for waiter in enteredWaiters { waiter.resume() }
        enteredWaiters = []
        if !isReleased {
            await withCheckedContinuation { gateWaiter = $0 }
        }
    }

    /// Suspends until `report()` has been entered (or returns immediately
    /// if it already was).
    func waitUntilEntered() async {
        guard !hasEntered else { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    /// Lets the parked `report()` return.
    func releaseGate() {
        isReleased = true
        gateWaiter?.resume()
        gateWaiter = nil
    }
}
