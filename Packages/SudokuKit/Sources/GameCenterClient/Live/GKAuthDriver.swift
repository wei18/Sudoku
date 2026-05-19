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

import Foundation
#if canImport(GameKit)
import GameKit
#if canImport(UIKit)
import UIKit
#endif
#endif

public actor GKAuthDriver: AuthDriver {

    private var didResolveHandshake = false
    private var pendingHandshake: CheckedContinuation<AuthOutcome, Never>?
    private var observerContinuations: [UUID: AsyncStream<AuthOutcome>.Continuation] = [:]
    private var didInstallHandler = false

    public init() {}

    public func performAuthentication() async -> AuthOutcome {
        installHandlerIfNeeded()
        return await withCheckedContinuation { continuation in
            if didResolveHandshake {
                // Already resolved earlier in this session — return the
                // cached latest outcome by yielding a synchronous read.
                continuation.resume(returning: currentOutcome())
                return
            }
            pendingHandshake = continuation
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

    // MARK: - Handler installation

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

    private func deliverOutcome(_ outcome: AuthOutcome) {
        cachedOutcome = outcome
        if !didResolveHandshake {
            didResolveHandshake = true
            pendingHandshake?.resume(returning: outcome)
            pendingHandshake = nil
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
