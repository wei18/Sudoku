// GKAuthDriver — the **only** file in this target that imports GameKit.
//
// Wraps `GKLocalPlayer.local.authenticateHandler` per Apple's documented
// pattern: assign a handler ONCE on app launch; GameKit fires it whenever
// the authentication state changes (initial sign-in, sign-out, parental
// controls toggle, etc.). The handler may be invoked multiple times.
//
// We translate every invocation into an `AuthOutcome` and feed two
// channels:
//   1. A latched single-shot `performAuthentication()` resolves on the
//      first definitive outcome (signed-in / signed-out / restricted /
//      error / cancelled). Subsequent invocations are routed only to (2).
//   2. `observeStateChanges()` continuously emits every subsequent outcome.
//
// On platforms where GameKit is unavailable (or while we deliberately
// stub out behaviour in unit-test builds), the driver collapses to a
// `.error("GameKit unavailable")` outcome so the rest of the system can
// reason about failure without #if-fencing every call site.
//
// Issue #766: `authenticateHandler` is GameKit's callback — if it simply
// never fires (hung network call inside GameKit itself), the continuation
// above used to wait forever, permanently withholding `resumeCandidate`
// for the whole session. `performAuthentication()` now races the
// continuation against `handshakeTimeout` (default 10s, injectable for
// tests). `didResolveHandshake` is the single source of truth for "has the
// continuation been resumed yet" — both the timeout path and a genuine
// GameKit callback go through `deliverOutcome(_:)`, which only resumes
// once. A genuine callback that lands first cancels the pending timeout
// task (no stray resume). A genuine callback that lands *after* the
// timeout already resolved is a no-op on `pendingHandshakes` (already
// empty) but still updates `cachedOutcome` and yields to
// `observerContinuations` — so downstream observers recover on their next
// refresh even though the original `performAuthentication()` caller
// already moved on. The timeout path resolves to the same degraded
// `.signedOut` outcome a real not-signed-in callback would produce, and
// reports through `errorReporter` with a distinct source
// ("GKAuthDriver.handshakeTimeout") so a stuck callback stays diagnosable
// in telemetry without adding a new `AuthOutcome` case (which would
// ripple through every exhaustive switch).
//
// `pendingHandshakes` is a multi-slot collection (CR on #766): several
// callers can legitimately race `performAuthentication()` on the same
// driver before the first outcome lands (GameRootViewModel.bootstrap()
// vs a game VM's submit path). A single-slot store would overwrite and
// permanently orphan the earlier caller's continuation — the exact hang
// class this fix exists to kill. All parked continuations resume together
// on the first outcome; one timeout task covers the whole parked cohort
// (a second caller parking while a timeout is already scheduled does not
// reset or duplicate it). A caller arriving after the timeout already
// resolved never parks at all — the `didResolveHandshake` short-circuit
// returns `currentOutcome()` (the cached `.signedOut`) synchronously.

import Foundation
#if canImport(GameKit)
import GameKit
#if canImport(UIKit)
import UIKit
#endif
#endif
public import Telemetry

public actor GKAuthDriver: AuthDriver {

    private var didResolveHandshake = false
    private var pendingHandshakes: [UUID: CheckedContinuation<AuthOutcome, Never>] = [:]
    private var handshakeTimeoutTask: Task<Void, Never>?
    private var observerContinuations: [UUID: AsyncStream<AuthOutcome>.Continuation] = [:]
    private var didInstallHandler = false

    private let handshakeTimeout: Duration
    private let errorReporter: any ErrorReporter

    /// - Parameters:
    ///   - handshakeTimeout: bound on how long `performAuthentication()`
    ///     waits for GameKit's `authenticateHandler` callback before
    ///     degrading to `.signedOut` (issue #766). Production default is
    ///     10s; tests inject a millisecond-scale value.
    ///   - errorReporter: unified error funnel (issue #67 pattern). The
    ///     timeout path reports through it with source
    ///     "GKAuthDriver.handshakeTimeout" so it stays distinguishable
    ///     from an ordinary not-signed-in outcome.
    public init(
        handshakeTimeout: Duration = .seconds(10),
        errorReporter: any ErrorReporter = NoopErrorReporter()
    ) {
        self.handshakeTimeout = handshakeTimeout
        self.errorReporter = errorReporter
    }

    public func performAuthentication() async -> AuthOutcome {
        installHandlerIfNeeded()
        return await withCheckedContinuation { continuation in
            if didResolveHandshake {
                // Already resolved earlier in this session — return the
                // cached latest outcome by yielding a synchronous read.
                continuation.resume(returning: currentOutcome())
                return
            }
            // Multi-slot: concurrent callers park side by side; a second
            // caller must never overwrite (= orphan) the first one's
            // continuation (CR on #766).
            pendingHandshakes[UUID()] = continuation
            scheduleHandshakeTimeoutIfNeeded()
        }
    }

    public func observeStateChanges() async -> AsyncStream<AuthOutcome> {
        installHandlerIfNeeded()
        let id = UUID()
        let (stream, continuation) = AsyncStream<AuthOutcome>.makeStream()
        observerContinuations[id] = continuation
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return stream
    }

    private func removeObserver(_ id: UUID) {
        observerContinuations.removeValue(forKey: id)
    }

    // MARK: - Handshake timeout (issue #766)

    private func scheduleHandshakeTimeoutIfNeeded() {
        // One timeout task covers every parked continuation: a second
        // caller parking while the first caller's deadline is pending must
        // not reset (extend) or duplicate the timer.
        guard handshakeTimeoutTask == nil else { return }
        let timeout = handshakeTimeout
        handshakeTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            await self?.resolveHandshakeTimeout()
        }
    }

    private func resolveHandshakeTimeout() async {
        // A genuine callback may have already resolved the handshake
        // between the timer firing and this actor hop landing — no-op.
        guard !didResolveHandshake else { return }
        await errorReporter.report(
            .gameCenterUnauthenticated,
            underlying: HandshakeTimeoutError(),
            source: "GKAuthDriver.handshakeTimeout"
        )
        // Re-check after the report: `await errorReporter.report(...)` is a
        // cross-actor suspension — a genuine GameKit callback can run
        // `deliverOutcome(realOutcome)` on this actor while the report is
        // in flight. Delivering `.signedOut` unconditionally here would
        // clobber `cachedOutcome` back to the degraded state and re-yield
        // the stale value to every observer stream (CR on #766).
        guard !didResolveHandshake else { return }
        deliverOutcome(.signedOut)
    }

    // MARK: - Handler installation

    /// Internal (not `private`) test-only seam (issue #766 tests): pre-marks
    /// the GameKit handler as already installed so `performAuthentication()`
    /// exercises the timeout/continuation state machine WITHOUT ever
    /// touching real `GKLocalPlayer.local`. That access hangs the MainActor
    /// synchronously (indefinitely) in an unentitled SwiftPM test runner —
    /// the same class of landmine as `CKContainer.default()` — so tests
    /// must never call `performAuthentication()` / `observeStateChanges()`
    /// without this seam.
    func suppressGameKitInstallForTesting() {
        didInstallHandler = true
    }

    private func installHandlerIfNeeded() {
        guard !didInstallHandler else { return }
        didInstallHandler = true
        #if canImport(GameKit)
        // GameKit requires this be set on the main thread the first time;
        // subsequent invocations fire on an arbitrary thread.
        Task { @MainActor [weak self] in
            GKLocalPlayer.local.authenticateHandler = { viewController, error in
                _ = viewController
                // viewController is non-nil when GameKit needs us to present
                // its sign-in UI. v1 surfaces an outcome regardless — UI
                // presentation responsibility belongs to the App layer
                // (plan.md Phase 9) and is intentionally NOT done here.
                let outcome = Self.mapGameKitState(error: error)
                Task { [weak self] in await self?.deliverOutcome(outcome) }
            }
        }
        #else
        Task { [weak self] in await self?.deliverOutcome(.error("GameKit unavailable")) }
        #endif
    }

    /// Internal (not `private`) so `@testable import GameCenterClient` can
    /// drive it directly — the only seam that lets tests simulate a
    /// genuine GameKit callback (prompt or late-after-timeout) without
    /// standing up real GameKit, which never calls back in an unentitled
    /// test runner (that hang is exactly what issue #766 is about).
    func deliverOutcome(_ outcome: AuthOutcome) {
        cachedOutcome = outcome
        if !didResolveHandshake {
            didResolveHandshake = true
            // Happy path: a callback that lands before the deadline
            // cancels the still-pending timeout task so it never fires.
            handshakeTimeoutTask?.cancel()
            handshakeTimeoutTask = nil
            // Resume the whole parked cohort — every concurrent
            // performAuthentication() caller gets the same first outcome.
            for continuation in pendingHandshakes.values {
                continuation.resume(returning: outcome)
            }
            pendingHandshakes = [:]
        }
        for continuation in observerContinuations.values {
            continuation.yield(outcome)
        }
    }

    private var cachedOutcome: AuthOutcome = .error("not yet resolved")

    private func currentOutcome() -> AuthOutcome { cachedOutcome }

    // MARK: - GameKit error mapping

    /// Map the (viewController?, error?) callback into our outcome enum.
    /// `error == nil && isAuthenticated == true` → signed in.
    /// `error == nil && isAuthenticated == false` → signed out.
    /// Otherwise inspect `GKError.Code`.
    nonisolated static func mapGameKitState(error: (any Error)?) -> AuthOutcome {
        #if canImport(GameKit)
        if let error {
            return mapError(error)
        }
        let local = GKLocalPlayer.local
        if local.isAuthenticated {
            return .signedIn(PlayerSummary(
                teamPlayerId: local.gamePlayerID,
                displayName: local.displayName.isEmpty ? local.alias : local.displayName
            ))
        }
        return .signedOut
        #else
        _ = error
        return .error("GameKit unavailable")
        #endif
    }

    #if canImport(GameKit)
    private static func mapError(_ error: any Error) -> AuthOutcome {
        let nsError = error as NSError
        if nsError.domain == GKError.errorDomain, let code = GKError.Code(rawValue: nsError.code) {
            // GKError.Code mapping table:
            //   .cancelled              → .cancelled
            //   .notAuthenticated       → .signedOut (user dismissed sign-in)
            //   .parentalControlsBlocked → .restricted
            //   .gameUnrecognized       → .unavailableInRegion (App Store
            //     guideline rejection / region block heuristic; see
            //     RegionMapper (Step 7.7) for the refined classification)
            //   .notSupported           → .unavailableInRegion
            //   everything else         → .error(raw code + description)
            switch code {
            case .cancelled: return .cancelled
            case .notAuthenticated: return .signedOut
            case .parentalControlsBlocked: return .restricted
            case .gameUnrecognized, .notSupported: return .unavailableInRegion
            default: return .error("\(code.rawValue): \(nsError.localizedDescription)")
            }
        }
        return .error("\(nsError.domain) #\(nsError.code): \(nsError.localizedDescription)")
    }
    #endif
}

/// Underlying error handed to `errorReporter` on the handshake-timeout path
/// (issue #766). Carries no payload — the distinct `source` string on the
/// `report(...)` call is what makes the timeout diagnosable; this type only
/// exists to satisfy `ErrorReporter.report(_:underlying:source:)`'s
/// non-optional `any Error` parameter.
private struct HandshakeTimeoutError: Error {}
